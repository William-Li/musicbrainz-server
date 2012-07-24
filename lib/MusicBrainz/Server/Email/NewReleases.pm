package MusicBrainz::Server::Email::NewReleases;
use Moose;
use namespace::autoclean;

use String::TT qw( strip tt );
use MusicBrainz::Server::Entity::Types;
use MusicBrainz::Server::Constants qw( $EMAIL_SUPPORT_ADDRESS );
use DBDefs;

has 'editor' => (
    isa => 'Editor',
    required => 1,
    is => 'ro',
    handles => {
        to => 'email',
    }
);

with 'MusicBrainz::Server::Email::Role';

sub subject { 'New releases from your watched artists' }

has 'releases' => (
    isa => 'ArrayRef[Release]',
    is => 'ro',
    required => 1
);

sub extra_headers {
    my $self = shift;
    return (
        'Reply-To' => $EMAIL_SUPPORT_ADDRESS,
        'References' => sprintf('<watched-%s@%s>', $self->editor->id, &DBDefs::WEB_SERVER_USED_IN_EMAIL),
        'In-Reply-To' => sprintf('<watched-%s@%s>', $self->editor->id, &DBDefs::WEB_SERVER_USED_IN_EMAIL),
        'Message-Id' => sprintf('<watched-%s-%d@%s>', $self->editor->id, time(), &DBDefs::WEB_SERVER_USED_IN_EMAIL)
    )
}

sub text {
    my $self = shift;
    return strip tt q{
[% FOR release=self.releases %]
[% release.name %] by [% release.artist_credit.name %] - released [% release.date.format %] on [% release.combined_format_name %]
[% self.server %]/release/[% release.gid %]
[% END %]
};
}

sub header {
    my $self = shift;
    return strip tt q{
This is a notification that artists you are watching have new releases
that have either just been released, or are due to be released in the near
future.
};
}

sub footer {
    my $self = shift;
    return strip tt q{
Please do not reply to this message.  If you need help, please see
[% self.server %]/doc/ContactUs
};
}

1;
