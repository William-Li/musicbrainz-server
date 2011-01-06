package MusicBrainz::Server::Controller::Edit;
use Moose;

BEGIN { extends 'MusicBrainz::Server::Controller' }

use Data::Page;
use DBDefs;
use MusicBrainz::Server::Types qw( $STATUS_OPEN );
use MusicBrainz::Server::Validation qw( is_positive_integer );

use aliased 'MusicBrainz::Server::EditRegistry';

with 'MusicBrainz::Server::Controller::Role::Load' => {
    model => 'Edit',
    entity_name => 'edit',
};

__PACKAGE__->config(
    paging_limit => 25,
);

=head1 NAME

MusicBrainz::Server::Controller::Moderation - handle user interaction
with moderations

=head1 DESCRIPTION

This controller allows editors to view moderations, and vote on open
moderations.

=head1 ACTIONS

=head2 moderation

Root of chained actions that work with a single moderation. Cannot be
called on its own.

=cut

sub base : Chained('/') PathPart('edit') CaptureArgs(0) { }

sub _load
{
    my ($self, $c, $edit_id) = @_;
    return unless is_positive_integer($edit_id);
    return $c->model('Edit')->get_by_id($edit_id);
}

sub show : Chained('load') PathPart('') RequireAuth
{
    my ($self, $c) = @_;
    my $edit = $c->stash->{edit};

    $c->model('Edit')->load_all($edit);
    $c->model('Vote')->load_for_edits($edit);
    $c->model('EditNote')->load_for_edits($edit);
    $c->model('Editor')->load($edit, @{ $edit->votes }, @{ $edit->edit_notes });
    $c->form(add_edit_note => 'EditNote');

    $c->stash->{template} = 'edit/index.tt';
}

sub enter_votes : Local RequireAuth
{
    my ($self, $c) = @_;

    my $form = $c->form(vote_form => 'Vote');
    if ($c->form_posted && $form->submitted_and_valid($c->req->params)) {
        my @submissions = @{ $form->field('vote')->value };
        my @votes = grep { $_->{vote} } @submissions;
        $c->model('Vote')->enter_votes($c->user->id, @votes);
        
        my @notes = grep { $_->{edit_note} } @submissions;
        for my $note (@notes) {
            $c->model('EditNote')->add_note(
                $note->{edit_id},
                {
                    editor_id => $c->user->id,
                    text => $note->{edit_note},
                });
        }
    }

    my $redir = $c->req->params->{url} || $c->uri_for_action('/edit/open_edits');
    $c->response->redirect($redir);
    $c->detach;
}

sub approve : Chained('load') RequireAuth(auto_editor)
{
    my ($self, $c) = @_;

    my $edit = $c->stash->{edit};
    if (!$edit->can_approve($c->user)) {
        $c->stash( template => 'edit/cannot_approve.tt' );
        $c->detach;
    }

    if($edit->no_votes > 0) {
        $c->model('EditNote')->load_for_edits($edit);
        my $left_note;
        for my $note (@{ $edit->edit_notes }) {
            next if $note->editor_id != $c->user->id;
            $left_note = 1;
            last;
        }

        unless($left_note) {
            $c->stash( template => 'edit/require_note.tt' );
            $c->detach;
        };
    }

    $c->model('Edit')->approve($edit, $c->user->id);
    $c->response->redirect($c->req->query_params->{url} || $c->uri_for_action('/edit/show', [ $edit->id ]));
}

sub cancel : Chained('load') RequireAuth
{
    my ($self, $c) = @_;

    my $edit = $c->stash->{edit};
    if (!$edit->can_cancel($c->user)) {
        $c->stash( template => 'edit/cannot_cancel.tt' );
        $c->detach;
    }
    $c->model('Edit')->cancel($edit);

    $c->response->redirect($c->req->query_params->{url} || $c->uri_for_action('/edit/show', [ $edit->id ]));
    $c->detach;
}

=head2 open

Show a list of open moderations

=cut

sub open : Local RequireAuth
{
    my ($self, $c) = @_;

    my $edits = $self->_load_paged($c, sub {
         $c->model('Edit')->find({ status => $STATUS_OPEN }, shift, shift);
    });

    $c->model('Edit')->load_all(@$edits);
    $c->model('Vote')->load_for_edits(@$edits);
    $c->model('EditNote')->load_for_edits(@$edits);
    $c->model('Editor')->load(map { ($_, @{ $_->votes, $_->edit_notes }) } @$edits);
    $c->form(add_edit_note => 'EditNote');

    $c->stash( edits => $edits );
}

sub search : Path('/search/edits') RequireAuth
{
    my ($self, $c) = @_;

    my $form = $c->form( form => 'Search::Edits' );
    if ($form->submitted_and_valid($c->req->query_params)) {
        my @types = @{ $form->field('type')->value };

        my $edits = $self->_load_paged($c, sub {
            return $c->model('Edit')->find({
                type   => [ map { split /,/ } @types ],
                status => $form->field('status')->value,
            }, shift, shift);
        });

        $c->model('Edit')->load_all(@$edits);
        $c->model('Vote')->load_for_edits(@$edits);
        $c->model('EditNote')->load_for_edits(@$edits);
        $c->model('Editor')->load(map { ($_, @{ $_->votes, $_->edit_notes }) } @$edits);
        $c->form(add_edit_note => 'EditNote');

        $c->stash(
            edits    => $edits,
            template => 'edit/search_results.tt'
        );
    }
}

=head2 conditions

Display a table of all edit types, and their relative conditions
for acceptance

=cut

sub edit_types : Path('/doc/Edit_Types')
{
    my ($self, $c) = @_;

    my %by_category;
    for my $class (EditRegistry->get_all_classes) {
        $by_category{$class->edit_category} ||= [];
        push @{ $by_category{$class->edit_category} }, $class;
    }

    for my $category (keys %by_category) {
        $by_category{$category} = [
            sort { $a->edit_name cmp $b->edit_name }
                @{ $by_category{$category} }
            ];
    }

    $c->stash(
        by_category => \%by_category,
        template => 'doc/edit_types.tt'
    );
}

sub edit_type : Path('/doc/Edit_Types') Args(1) {
    my ($self, $c, $edit_type) = @_;

    my $class = EditRegistry->class_from_type($edit_type);
    my $id = 'Edit Type/$class->edit_name';
    $id =~ s/ /_/g;

    my $version = $c->model('WikiDocIndex')->get_page_version($id);
    my $page = $c->model('WikiDoc')->get_page($id, $version);

    $c->stash(
        edit_type => $class,
        template => 'doc/edit_type.tt',
        page => $page
    );
}

1;
