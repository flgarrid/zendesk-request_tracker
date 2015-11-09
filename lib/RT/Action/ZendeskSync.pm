package RT::Action::ZendeskSync;

    use strict;
    use warnings;
    use base 'RT::Action';
    use LWP::UserAgent;
	use JSON;
	use MIME::Base64;

    sub Prepare {
        my $self = shift;

        return 1;
    }

    sub Commit {
        my $self = shift;
		my $ZendeskUser = 'default@default.com'; # Zendesk User's email (has to be an Admintrator)
		my $ZendeskURL = 'https://xxxxxx.zendesk.com'; # Zendesk Account URL (https!)
		my $RTURL = 'http://xxxxxxxxxx.xxx'; # RT's URL
		my $ZendeskToken = 'XXXXXXXXXXXXXXXXXXXXXXXXXXXXX'; # Zendesk API Token
		my $XZendeskAccountID = '387974e'; # Zendesk account ID (sent automatically in every outgoing email)
		
		my @tags_data = ('request_tracker'); # Any tag that you want to set by default
		
		my $credentials = encode_base64($ZendeskUser.'/token:'.$ZendeskToken);

		my $Ticket = $self->TicketObj;

		my $ua = LWP::UserAgent->new(ssl_opts =>{ verify_hostname => 0 });

		my $resolved_message = '';
		my $last_content = '';
		my $user_date = '';

		my $inMessage = $self->TransactionObj->Attachments->First;

		if($inMessage->GetHeader('X-Zendesk-From-Account-ID') eq $XZendeskAccountID){
		   my $Attachments = $self->TransactionObj->Attachments;
		   while (my $a = $Attachments->Next) {  
			  my $zd_id = $a->Content;
			  $zd_id =~ /(?:##zendesk_id )([0-9]*)/;
			  if($1){
				  $self->TicketObj->AddCustomFieldValue(Field => 'Zendesk_ID',Value => $1,RecordTransaction => 0 ); 
					my $rt_id = $Ticket->id;
					my $header = '';
					   $header .= 'Request Tracker #: '.$Ticket->id;
					   $header .= "\n";
					   $header .= "Link to RT: $RTURL/Ticket/Display.html?id=".$Ticket->id;

					my %data = (
						ticket => {
							comment => {
								body => $header,
								public => 0,
							},
							external_id=>$rt_id,
						},
					);
					my $data = encode_json(\%data);

					my $response = $ua->put("$ZendeskURL/api/v2/tickets/$1.json",
											 'Content' => $data,
											 'Content-Type' => 'application/json',
											 'Authorization' => "Basic $credentials");
					#If you want to set a tag on this new ticket
					$response = $ua->put("$ZendeskURL/api/v2/tickets/$1/tags.json",
											 'Content' => '{ "tags": ["rt"] }',
											 'Content-Type' => 'application/json',
											 'Authorization' => "Basic $credentials");

					for ($Ticket->Requestors->MemberEmailAddresses) 
					{ 
						$Ticket->DeleteWatcher( 
						  Type => 'Requestor', 
						  Email => $_, 
						  Silent => 1); 
					}
					$zd_id =~ /(?:##zendesk_requester_email )(.*@.*)/;
					$self->TicketObj->AddWatcher( 
					Type => 'Requestor', 
					Email => $1, 
					Silent => 1);
							  last;
			  }
		  }
		}
        return 1;
    }

    1;