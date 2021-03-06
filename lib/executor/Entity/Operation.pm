#    Copyright © 2011-2013 Hedera Technology SAS
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Maintained by Dev Team of Hedera Technology <dev@hederatech.com>.

=pod
=begin classdoc

This module is the operations abstract class.
It defines the operation execution interface to implement in
the concrete operations.

=end classdoc
=cut

package Entity::Operation;
use base Entity;

use strict;
use warnings;

use Kanopya::Database;
use General;
use Entity::Workflow;
use ParamPreset;
use OldOperation;

use Hash::Merge;
use TryCatch;
use Data::Dumper;
use Log::Log4perl "get_logger";
my $log = get_logger("");


use constant OPERATION_STATES => (
    'ready',
    'processing',
    'prereported',
    'postreported',
    'waiting_validation',
    'validated',
    'failed',
    'cancelled',
    'succeeded',
    'pending',
    'statereported',
    'interrupted',
    'timeouted'
);


use constant ATTR_DEF => {
    operationtype_id => {
        pattern      => '^\d+$',
        is_mandatory => 1,
    },
    state => {
        pattern      => '^' . join('|', Entity::Operation::OPERATION_STATES) . '$',
        default      => 'pending',
        is_mandatory => 0,
    },
    workflow_id => {
        pattern      => '^\d+$',
        is_mandatory => 0,
    },
    priority => {
        pattern      => '^\d+$',
        is_mandatory => 0,
    },
    creation_date => {
        pattern      => '^.*$',
        is_mandatory => 0,
    },
    creation_time => {
        pattern      => '^.*$',
        is_mandatory => 0,
    },
    hoped_execution_time => {
        pattern      => '^.*$',
        is_mandatory => 0,
    },
    execution_rank => {
        pattern      => '^\d+$',
        is_mandatory => 0,
    },
    label => {
        is_virtual   => 1,
    },
    type => {
        is_virtual   => 1,
    },
};

sub getAttrDef { return ATTR_DEF; }

sub methods {
    return {
        validate => {
            description => 'Validate the operation execution.',
        },
        deny => {
            description => 'Deny the operation execution.',
        }
    };
}


=pod
=begin classdoc

@constructor

Create a new operation from an operation type and a priority.
If params are given in parameters, serialize its in database.

@param operationtype the operation type
@param priority      the execution priority of the operation

@optional params      the operation parameters hash
@optional workflow_id the workflow that the operation belongs to
@optional harmless    flag to set the operatio as harmless
@optional workflow_manager the workflow_manager component
@optional group       the operation group

@return the operation instance.

=end classdoc
=cut

sub new {
    my ($class, %args) = @_;
    my $self;

    General::checkParams(args     => \%args,
                         required => [ 'priority', 'operationtype' ],
                         optional => { 'workflow_id'      => undef,
                                       'params'           => undef,
                                       'harmless'         => 0,
                                       'group'            => undef,
                                       'workflow_manager' => undef,
                                       'timeout'          => undef });

    # If workflow not defined, initiate a new one with parameters
    my $workflow;
    if (defined $args{workflow_id}) {
        $workflow = Entity::Workflow->get(id => $args{workflow_id});
    }
    else {
        General::checkParams(args => \%args, required => [ 'workflow_manager' ]);
        $workflow = Entity::Workflow->new(workflow_manager => $args{workflow_manager}, timeout => $args{timeout});
    }

    # Compute the execution time if required
    my $hoped_execution_time = defined $args{hoped_execution_time}
                                   ? time + $args{hoped_execution_time}
                                   : undef;

    # Get the next execution rank within the creation transation.
    Kanopya::Database::beginTransaction;

    try {
        $log->debug("Enqueuing new operation <" . $args{operationtype}->label .
                    ">, in workflow <" . $workflow->id . ">");
        $self = $class->SUPER::new(operationtype_id     => $args{operationtype}->id,
                                   state                => "pending",
                                   execution_rank       => $workflow->getNextRank(),
                                   workflow_id          => $workflow->id,
                                   priority             => $args{priority},
                                   harmless             => $args{harmless},
                                   creation_date        => \"CURRENT_DATE()",
                                   creation_time        => \"CURRENT_TIME()",
                                   hoped_execution_time => $hoped_execution_time,
                                   owner_id             => Kanopya::Database::currentUser);

        if (defined $args{group}) {
            $self->operation_group_id($args{group}->id);
        }
        if (defined $args{params}) {
            $self->serializeParams(params => $args{params});
        }

        # Set the name of the workflow name with operation label
        if (! $workflow->workflow_name) {
            $workflow->workflow_name($self->label);
        }
    }
    catch (Kanopya::Exception $err) {
        Kanopya::Database::rollbackTransaction;
        $err->rethrow();
    }
    catch ($err) {
        Kanopya::Database::rollbackTransaction;
        throw Kanopya::Exception(error => $err);
    }

    Kanopya::Database::commitTransaction;

    return $self;
}


=pod
=begin classdoc

Serialize the params hash in database. All scalar values are jsonifyed,
the entities objects of the context are serialized by there ids.

@param params the params hash to serialize

=end classdoc
=cut

sub serializeParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'params' ]);

    PARAMS:
    while(my ($key, $value) = each %{ $args{params} }) {
        if (not defined $value) { next PARAMS; }

        # Context params must Entity instances, which will be serialized
        # as an entity id, and re-instanciated at pop params.
        if ($key eq 'context') {
            if (ref($value) ne 'HASH') {
                throw Kanopya::Exception::Internal(
                          error => "Params 'context' must be a hash with Entity intances as values."
                      );
            }

            # Serialize each context entities
            CONTEXT:
            while(my ($subkey, $subvalue) = each %{ $value }) {
                # If tag is 'context', this is entities params
                if (not defined $subvalue) {
                    $log->warn("Context value anormally undefined: $subkey");
                    delete $value->{$subkey};
                    next CONTEXT;
                }
                if (! ref ($subvalue) or ! ($subvalue->isa('Entity') or $subvalue->isa('EEntity'))) {
                    throw Kanopya::Exception::Internal(
                              error => "Can not serialize param <$subkey> of type <context>' " .
                                       "that is not an entity <$subvalue>."
                          );
                }
                try {
                    $subvalue->reload();
                }
                catch (Kanopya::Exception::Internal::NotFound $err) {
                    $log->warn("Entity $subvalue <" . $subvalue->id . "> does not exists any more, " .
                               "removing it from context.");
                    delete $value->{$subkey};
                    next CONTEXT;
                }
                catch ($err) {
                    $err->rethrow()
                }
                $value->{$subkey} = $subvalue->id;
            }
        }
    }

    try {
        # Update the existing presets, create its instead
        if (defined $self->param_preset) {
            $self->param_preset->update(params => $args{params}, override => 1);
        }
        else {
            $self->param_preset_id(ParamPreset->new(params => $args{params})->id);
        }
    }
    catch ($err) {
        $log->error("Unable to serialize params for operation " . $self->label . " : $err");
    }
}


=pod
=begin classdoc

Unserialize from database to a params hash. Context entities are instantiated
form there ids.

@optional skip_not_found ignore errors when entities do not exists any more

@return the params hash

=end classdoc
=cut

sub unserializeParams {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { 'skip_not_found' => 0 });

    my $params = defined $self->param_preset ? $self->param_preset->load() : {};
    if (defined $params->{context}) {
        # Unserialize context entities
        CONTEXT:
        while(my ($key, $value) = each %{ $params->{context} }) {
            # Try to instanciate value as an entity.
            try {
                $params->{context}->{$key} = Entity->get(id => $value);
            }
            catch ($err) {
                # Can skip errors on entity instanciation. Could be usefull when
                # loading context that containing deleted entities.
                if (not $args{skip_not_found}) {
                    throw Kanopya::Exception::Internal(
                              error => "Workflow <" . $self->id .
                                       ">, context param <$value>, seems not to be an entity id.\n$err"
                          );
                }
                else {
                    delete $params->{context}->{$key};
                    next CONTEXT;
                }
            }
        }
    }
    return $params;
}


=pod
=begin classdoc

Globally lock the entities of the context. Insert an entry in Entitylock, if the insert
fail, then a lock is already in db for the entity.

=end classdoc
=cut

sub lockContext {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { 'skip_not_found' => 0 });

    my $params = $self->unserializeParams(skip_not_found => $args{skip_not_found});

    Kanopya::Database::beginTransaction;
    try {
        for my $entity (values %{ $params->{context} }) {
            $log->debug("Trying to lock entity <$entity>");
            $entity->lock(consumer => $self->workflow);
        }
    }
    catch ($err) {
        Kanopya::Database::rollbackTransaction;
        $err->rethrow;
    }
    Kanopya::Database::commitTransaction;
}


=pod
=begin classdoc

Remove the possible lock objects related to the entities of the context.

=end classdoc
=cut

sub unlockContext {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, optional => { 'skip_not_found' => 0 });

    my $params = $self->unserializeParams(skip_not_found => $args{skip_not_found});

    Kanopya::Database::beginTransaction;
    for my $key (keys %{ $params->{context} }) {
        my $entity = $params->{context}->{$key};
        $log->debug("Trying to unlock entity <$key>, id <" . $entity->id . ">");
        try {
            $entity->unlock(consumer => $self->workflow);
        }
        catch ($err) {
            $log->debug("Unable to unlock context param <$key>\n$err");
        }
    }
    Kanopya::Database::commitTransaction;
}


=pod
=begin classdoc

Validate the operation that the execution has been stopped because it require validation.

=end classdoc
=cut

sub validate {
    my ($self, %args) = @_;

    # Push a message on the channel 'operation_result' to continue the workflow
    $self->workflow->workflow_manager->terminate(operation_id => $self->id, status => 'validated');

    $self->removeValidationPerm();
}


=pod
=begin classdoc

Deny the operation that the execution has been stopped because it require validation.

=end classdoc
=cut

sub deny {
    my ($self, %args) = @_;

    $self->workflow->cancel();

    # Push a message on the channel 'operation_result' to continue the workflow
    $self->workflow->workflow_manager->terminate(
        operation_id => $self->id, status => 'waiting_validation'
    );

    $self->removeValidationPerm();
}


=pod
=begin classdoc

Add permissions required by the consumer user to validate/deny the operation.

=end classdoc
=cut

sub addValidationPerm {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'consumer' ]);

    $self->addPerm(consumer => $args{consumer}, method => 'validate');
    $self->addPerm(consumer => $args{consumer}, method => 'deny');
}


=pod
=begin classdoc

Remove permissions required by the consumer user to validate/deny the operation.

=end classdoc
=cut

sub removeValidationPerm {
    my ($self, %args) = @_;

    $self->removePerm(method => 'validate');
    $self->removePerm(method => 'deny');
}


=pod
=begin classdoc

Remove the related param preset from db.

=end classdoc
=cut

sub removePresets {
    my ($self, %args) = @_;

    # Firstly empty the old pattern
    my $presets = $self->param_preset;
    if ($presets) {
        # Detach presets from the policy
        $self->setAttr(name => 'param_preset_id', value => undef, save => 1);

        # Remove the preset
        $presets->remove();
    }
}


=pod
=begin classdoc

Build the operation label from parameters content

@return the operation label

=end classdoc
=cut

sub label {
    my ($self, %args) = @_;

    my $type = $self->operationtype;
    if ($type->operationtype_label) {
        my $params = $self->unserializeParams(skip_not_found => 1);
        return $self->workflow->formatLabel(
                   params      => {
                       context => delete $params->{context},
                       params  => $params,
                   },
                   description => $type->operationtype_label
               );
    }
    return $type->operationtype_name;
}


=pod
=begin classdoc

Shortcut vitual attribute to get the operation type name.

@return the operation type name

=end classdoc
=cut

sub type {
    my ($self, %args) = @_;

    return $self->operationtype->operationtype_name;
}


=pod
=begin classdoc

Alias for the operation constructor.

@return the operation instance

=end classdoc
=cut

sub enqueue {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => [ 'priority', 'operationtype' ]);

    return Entity::Operation->new(%args);
}


=pod
=begin classdoc

Override the parent method to fill to old operations with the deleted one.

=end classdoc
=cut

sub delete {
    my ($self, %args) = @_;

    # Uncomment this line if we do not want to keep old parameters
    # $self->removePresets();

    # Then create the old_operation from the operation
    OldOperation->new(
        operation_id     => $self->id,
        operationtype_id => $self->operationtype_id,
        workflow_id      => $self->workflow_id,
        user_id          => $self->owner_id,
        priority         => $self->priority,
        creation_date    => $self->creation_date,
        creation_time    => $self->creation_time,
        execution_date   => \"CURRENT_DATE()",
        execution_time   => \"CURRENT_TIME()",
        execution_status => $self->state,
        param_preset_id  => $self->param_preset_id,
    );

    # Delete the corresponding operation group if
    # it is the last remaining operation in the group
    if (defined $self->operation_group && scalar($self->operation_group->operations) <= 1) {
        $self->operation_group->delete();
    }
    $self->SUPER::delete();
}


=pod
=begin classdoc

Update the hoped execution time of the operation. Usefull while reporting
the operation execution in the future.

=end classdoc
=cut

sub setHopedExecutionTime {
    my ($self, %args) = @_;

    General::checkParams(args => \%args, required => ['value']);

    my $t = time + $args{value};
    $self->hoped_execution_time($t);
}

1;
