package RT::Condition::ZendeskUpdate;

    use strict;
    use warnings;
    use base 'RT::Condition';

    sub IsApplicable {
        #return 0 if $self->TransactionObj->Creator == [zendesk_user_id]; # if you have created a dedicated Zendesk user in RT, replace zendesk_user_id with the user's id in RT
		return 1 if $self->TicketObj->FirstCustomFieldValue('Zendesk_ID') ne ''; 
		return 0;
    }

    1; 