package RT::Action::ZendeskUpdate;

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

		my $batch = $Ticket->TransactionBatch;

		my $response;
		my $data;
		my $ua = LWP::UserAgent->new(ssl_opts =>{ verify_hostname => 0 });

		my $ticket_id = $Ticket->FirstCustomFieldValue('Zendesk_ID'); #always reads from this CF

		my $create = (grep { ($_->Type eq 'Create')? 1: 0;} @$batch)[0];
		if($create && ref($create)){
		   return 1;
		}

		my $queuechg = (grep { ($_->Type eq 'Set' && $_->Field eq 'Queue')? 1: 0;}@$batch)[0];

		my $queue = RT::Queue->new(RT::SystemUser);
		my $unassign = 0;
		if($queuechg && ref($queuechg)){
		   $queue->Load($queuechg->NewValue);
		}else{
		   $queue->Load($Ticket->QueueObj->id);
		}

		my $queueDescription = $queue->Description;

		my $status = $Ticket->Status;

		my $resolved_message = '';
		my $last_content = '';
		my $user_date = '';

		my $comment = (grep { ($_->Type eq 'Correspond' || $_->Type eq 'Comment')? 1: 0;} @$batch)[0];
		if($comment && ref($comment)){

		   my $res = '';
		   my $Attachments = $comment->Attachments;
		   while (my $a = $Attachments->Next) {
		   
			  return 1 if $a->GetHeader('X-Zendesk-From-Account-ID') eq $XZendeskAccountID;
			  
			  if($a->ContentType =~
					   m!^(text/html|text/plain|message|text$)!i){
			  my $content = $a->Content;
			  $content =~ s/<.+?>//sg;  # strip HTML tags from text/html
			  if($content && $user_date ne $a->CreatorObj->id.$a->CreatedObj->ISO){

			  $user_date = $a->CreatorObj->id.$a->CreatedObj->ISO;
			  $content =~ s/##- Please type your reply above this line -##//g;
			  $content =~ s/&nbsp;/ /g;
			  $content =~ s/(^\s+$)+//mg;

			  next if $last_content eq $content;
			  $last_content = $content;

			  my $email = '';
			  my $name = '';
			  $email = $a->CreatorObj->EmailAddress;
			  $name = $a->CreatorObj->RealName||(split /@/, $a->CreatorObj->EmailAddress)[0];

		my %data = (
			user => {
				name => $name,
				email => $email,
				verified => 1,
			},
		);

		$data = encode_json(\%data);

		$response = $ua->post("$ZendeskURL/api/v2/users.json",
								 'Content' => $data,
								 'Content-Type' => 'application/json',
								 'Authorization' => "Basic $credentials");

			  $resolved_message .= "From: ";
			  $resolved_message .= $a->CreatorObj->RealName?$a->CreatorObj->RealName.' ('.$a->CreatorObj->EmailAddress.')' : $a->CreatorObj->EmailAddress;
			  $resolved_message .= "\n";
			  $resolved_message .= "\n";
			  $resolved_message .= "$content";

			  }
			 }
			 if($a->Filename ne ''){
			 my $filename = $a->Filename;
			 $filename =~ s/ /%20/g;
			 $res .= "Attachments:\n" unless ($res);
			 $res .= "$RTURL/Ticket/Attachment/". $a->TransactionId ."/". $a->id ."/". $filename;
			 }
		   }
			if($res){
			$resolved_message .= "\n";
			$resolved_message .= "---";
			$resolved_message .= "\n";
			$resolved_message .= $res;
			}
		}


		my $statuschg = (grep { ($_->Type eq 'Status')? 1: 0;} @$batch)[0];
		if($statuschg && ref($statuschg)){
		   $status = $statuschg->NewValue;
		}

		if($status eq 'resolved'||$status eq 'not_applicable'){
		   $status = 'solved';
		}elsif($status eq 'stalled'){
		   $status = 'hold';
		}

		my $priority_data = '';
		my $Queue = $queue->Name;

		my @custom_fields_data = ();
		"a" =~ /a/;

		# You can set as many custom fields as you need
		
		#if($self->TicketObj->FirstCustomFieldValue('DEMO') ne ''){
		#   push @custom_fields_data, ({id=>1111111111, value=>$self->TicketObj->FirstCustomFieldValue('DEMO')});
		#}

		"a" =~ /a/;

		my %data = (
			ticket => {
				comment => {
					body => $resolved_message,
					public => 0,
				},
				status => $status,
				custom_fields=> \@custom_fields_data,
			},
		);
		if($resolved_message eq ''){
		   delete $data{ticket}{comment};
		}

		my $data = encode_json(\%data);

		my $url = "$ZendeskURL/api/v2/tickets/$ticket_id.json";

		$response = $ua->put($url,
								 'Content' => $data,
								 'Content-Type' => 'application/json',
								 'Authorization' => "Basic $credentials");

		$response = $ua->get($url,'Authorization' => "Basic $credentials");
		my $response_json = decode_json($response->content());
		
		#Follow Up Ticket created if needed
		
		if($response_json->{'ticket'}->{'status'} eq 'closed'){
			if($resolved_message eq ''){
			   my $transactions = $Ticket->Transactions;
			   $transactions->Limit( FIELD => 'Type', VALUE => 'Correspond', ENTRYAGGREGATOR => 'OR', OPERATOR => '=' );
			   $transactions->Limit( FIELD => 'Type', VALUE => 'Comment', ENTRYAGGREGATOR => 'OR', OPERATOR => '=' );
			   $transactions->Limit( FIELD => 'Type', VALUE => 'Create', ENTRYAGGREGATOR => 'OR', OPERATOR => '=' );
			   $transactions->OrderByCols (
						   { FIELD => 'Created',  ORDER => 'DESC' },
						   { FIELD => 'id',     ORDER => 'DESC' },
						   );
			   $resolved_message = $transactions->First->Attachments->First->Content;
			   if($resolved_message eq ''){
					$resolved_message = 'Ticket Follow Up #'.$ticket_id.'\n\nNew information attached.';
			   }
			}
			$response = $ua->post('$ZendeskURL/api/v2/requests.json','Content' => '{"request": {"via_followup_source_id": '.$ticket_id.',"status": "'.$status.'", "comment": {"body": "'.$resolved_message.'"}}}','Content-Type' => 'application/json','Authorization' => "Basic $credentials");
			$response_json = decode_json($response->content());
			if($response_json->{'request'}->{'id'}){
			   $self->TicketObj->AddCustomFieldValue(Field => 'Zendesk_ID',Value => $response_json->{'request'}->{'id'},RecordTransaction => 0 );
			   $ua->put('$ZendeskURL/api/v2/tickets/'.$response_json->{'request'}->{'id'}.'.json','Content' => '{"ticket":{"external_id": '.($Ticket->id).'}}','Content-Type' => 'application/json','Authorization' => "Basic $credentials");
			}
		}

        return 1;
    }

    1;