package LANraragi::Controller::Edit;
use Mojo::Base 'Mojolicious::Controller';

use File::Basename;
use Redis;
use Encode;
use Template;
use Mojo::JSON qw(decode_json);

use LANraragi::Utils::Generic;
use LANraragi::Utils::Archive;
use LANraragi::Utils::Database;

use LANraragi::Model::Config;

#Deletes the archive with the given id from redis, and the matching archive file.
sub delete_metadata_and_file {
    my $self = $_[0];
    my $id   = $_[1];

    my $redis = $self->LRR_CONF->get_redis();

    my $filename = $redis->hget( $id, "file" );
    $filename = LANraragi::Utils::Database::redis_decode($filename);

    $redis->del($id);

    $redis->quit();

    if ( -e $filename ) {
        unlink $filename;

        #Trigger a JSON rebuild.
        LANraragi::Utils::Database::invalidate_cache();

        return $filename;
    }

    return "0";

}

sub save_metadata {
    my $self = shift;

    my $id    = $self->req->param('id');
    my $title = $self->req->param('title');
    my $tags  = $self->req->param('tags');

    #clean up the user's inputs and encode them.
    ( LANraragi::Utils::Generic::remove_spaces($_) )   for ( $title, $tags );
    ( LANraragi::Utils::Generic::remove_newlines($_) ) for ( $title, $tags );

    #Input new values into redis hash.
    #prepare the hash which'll be inserted.
    my %hash = (
        title => encode_utf8($title),
        tags  => encode_utf8($tags)
    );

    my $redis = $self->LRR_CONF->get_redis();

#for all keys of the hash, add them to the redis hash $id with the matching keys.
    $redis->hset( $id, $_, $hash{$_}, sub { } ) for keys %hash;
    $redis->wait_all_responses;

    #Trigger a JSON rebuild.
    LANraragi::Utils::Database::invalidate_cache();

    $self->render(
        json => {
            id        => $id,
            operation => "edit",
            success   => 1
        }
    );
}

sub delete_archive {
    my $self = shift;
    my $id   = $self->req->param('id');

    my $delStatus = &delete_metadata_and_file( $self, $id );

    #Trigger a JSON rebuild.
    LANraragi::Utils::Database::invalidate_cache();

    $self->render(
        json => {
            id        => $id,
            operation => "delete",
            success   => $delStatus
        }
    );
}

sub index {
    my $self = shift;

    #Does the passed file exist in the database?
    my $id = $self->req->param('id');

    my $redis = $self->LRR_CONF->get_redis();

    if ( $redis->hexists( $id, "title" ) ) {
        my %hash = $redis->hgetall($id);

        my ( $name, $title, $tags, $file, $thumbhash ) =
          @hash{qw(name title tags file thumbhash)};

        ( $_ = LANraragi::Utils::Database::redis_decode($_) )
          for ( $name, $title, $tags, $file );

        #Build plugin listing
        my @plugins = LANraragi::Model::Plugins::plugins;

        #Plugin list is an array of hashes
        my @pluginlist = ();

        foreach my $plugin (@plugins) {
            my %pluginfo = $plugin->plugin_info();
            push @pluginlist, \%pluginfo;
        }

        $redis->quit();

        $self->render(
            template  => "edit",
            id        => $id,
            name      => $name,
            arctitle  => $title,
            tags      => $tags,
            file      => $file,
            thumbhash => $thumbhash,
            type      => ($hash{'type'} or "archive"),
            pages     => decode_json( $redis->hget( $id, "pages" ) ),
            plugins   => \@pluginlist,
            title     => $self->LRR_CONF->get_htmltitle,
            cssdrop   => LANraragi::Utils::Generic::generate_themes
        );
    }
    else { $self->redirect_to('index') }
}

1;
