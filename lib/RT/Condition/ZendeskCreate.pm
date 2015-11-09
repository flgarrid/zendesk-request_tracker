package RT::Condition::ZendeskCreate;

    use strict;
    use warnings;
    use base 'RT::Condition';

    sub IsApplicable {
        my $self = shift;

        return 0 if $self->TicketObj->FirstCustomFieldValue('Zendesk_ID') ne '';

		my $ququeDescription = $self->TicketObj->QueueObj->Description;

		if($self->TransactionObj->Type eq "Set" && $self->TransactionObj->Field eq "Queue"){
		   my $QueueObj = RT::Queue->new(RT::SystemUser);
		   $QueueObj->Load($self->TransactionObj->NewValue);
		   $ququeDescription = $QueueObj->Description;
		}
		if($self->TransactionObj->Type eq "Create"){
		   $ququeDescription = $self->TicketObj->QueueObj->Description;
		}

		return 1 if index($ququeDescription, '[Zendesk]') != -1;
		return 0;
    }

    1; 