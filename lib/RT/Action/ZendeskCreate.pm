package RT::Action::ZendeskCreate;

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
		
		my @tags_data = ('request_tracker'); # Any tag that you want to set by default
		
		my $credentials = encode_base64($ZendeskUser.'/token:'.$ZendeskToken);

		# New ticket info
		my $Queue = $self->TicketObj->QueueObj->Name;
		my $queueDescription = $self->TicketObj->QueueObj->Description;
		if($self->TransactionObj->Type eq "Set" && $self->TransactionObj->Field eq "Queue"){
		   my $QueueObj = RT::Queue->new(RT::SystemUser);
		   my $res = $QueueObj->Load($self->TransactionObj->NewValue);
		   $Queue = $QueueObj->Name;
		   $queueDescription = $QueueObj->Description;
		}
		if($self->TransactionObj->Type eq "Create"){
		   $Queue = $self->TicketObj->QueueObj->Name;
		   $queueDescription = $self->TicketObj->QueueObj->Description;
		}
		my $Ticket = $self->TicketObj;
		my $Transaction = $self->TransactionObj;
		my $subject = $Ticket->Subject;
		my $body = "Request created";  #You can change this if you want to
		my $status = $Ticket->Status;
		
		#status mapping - customize as needed
		if($status eq 'resolved'){
		   $status = 'solved';
		}elsif($status eq 'stalled'){
		   $status = 'hold';
		}
		
		
		
		my $email = '';
		if($Ticket->Requestors->UserMembersObj->First){
			 $email = $Ticket->Requestors->UserMembersObj->First->EmailAddress;
		}
		if($email eq ''){
		   $email = $ZendeskUser; 
		}
		my $name = '';
		if($Ticket->Requestors->UserMembersObj->First){
		   $name = $Ticket->Requestors->UserMembersObj->First->RealName;
		}
		if($name eq ''||length($name)>255){
		   my ($key, $value) = split /\s*@\s*/, $email; #simple way to extract the user's email alias
		   $name = $key;
		}
		my $rt_id = $Ticket->id;
		my $created_at = $Ticket->CreatedObj->ISO;
		$created_at =~ tr/ /T/;
		$created_at .= 'Z';
		$name = join ' ', map { ucfirst($_) } split '\s', $name;

		my %data = (
			ticket => {
				subject => $subject,
				external_id => $rt_id,
				created_at => $created_at,
				status => $status,
				comment => {
					body => $body,
				},
				requester => {
					name => $name,
					email => $email,
				},
			},
		);

		if($email !~ m/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-zA-Z]{2,4}$/){ #check if it's a valid email (simple)
		   delete $data{ticket}{requester}{email};
		}

		# Encode the data structure to JSON
		my $data = encode_json(\%data);

		# Create the user agent and make the request
		my $ua = LWP::UserAgent->new(ssl_opts =>{ verify_hostname => 0 });
		my $response = $ua->post($ZendeskURL.'/api/v2/tickets.json',
								 'Content' => $data,
								 'Content-Type' => 'application/json',
								 'Authorization' => "Basic $credentials");

		my $response_json = decode_json($response->content());

		$self->TicketObj->AddCustomFieldValue(Field => 'Zendesk_ID',Value => $response_json->{'ticket'}->{'id'},RecordTransaction => 0 );
		my $ticket_id = $response_json->{'ticket'}->{'id'};

		#--------------------------------------------------#


		my $header = '';
		   $header .= 'Request Tracker #: '.$Ticket->id;
		   $header .= "\n";
		   $header .= "Link to RT: $RTURL/Ticket/Display.html?id=".$Ticket->id;
		   $header .= "\n";
		   $header .= "\n";
		   $header .= "---";
		   $header .= "\n";

		#--------------------------------------------------#

		   my $res = '';
		   my $Attachments = RT::Attachments->new( $Transaction->CurrentUser );
		   $Attachments->Columns( qw(id TransactionId Filename ContentType Created));
		   my $transactions = $Attachments->NewAlias('Transactions');
		   $Attachments->Join(
			   ALIAS1 => 'main',
			   FIELD1 => 'TransactionId',
			   ALIAS2 => $transactions,
			   FIELD2 => 'id'
		   );
		   my $tickets = $Attachments->NewAlias('Tickets');
		   $Attachments->Join(
			   ALIAS1 => $transactions,
			   FIELD1 => 'ObjectId',
			   ALIAS2 => $tickets,
			   FIELD2 => 'id'
		   );
		   $Attachments->Limit(
			   ALIAS => $transactions,
			   FIELD => 'ObjectType',
			   VALUE => 'RT::Ticket'
		   );
		   $Attachments->Limit(
			   ALIAS => $tickets,
			   FIELD => 'EffectiveId',
			   VALUE => $Ticket->id
		   );
		   $Attachments->Limit( FIELD => 'Filename', OPERATOR => '!=', VALUE => '' );
		   while (my $a = $Attachments->Next) {
			 my $filename = $a->Filename;
			 $filename =~ s/ /%20/g;
			 $res .= "Attachments:\n" unless ($res);
			 $res .= "$RTURL/Ticket/Attachment/". $a->TransactionId ."/". $a->id ."/". $filename;
		   }
			if($res){
			 $res .= "\n";
			 $res .= "\n";
			 $res .= "---";
			 $res .= "\n";
		  }

		#--------------------------------------------------#

		  my $resolved_message = '';
		  my $last_content = '';
		  my $user_date ='';
		 
		  my $transactions = $Ticket->Transactions;
		 
		  $transactions->Limit( FIELD => 'Type', VALUE => 'Correspond', ENTRYAGGREGATOR => 'OR', OPERATOR => '=' );
		  $transactions->Limit( FIELD => 'Type', VALUE => 'Comment', ENTRYAGGREGATOR => 'OR', OPERATOR => '=' );
		  $transactions->Limit( FIELD => 'Type', VALUE => 'Create', ENTRYAGGREGATOR => 'OR', OPERATOR => '=' );
		   $transactions->OrderByCols (
					   { FIELD => 'Created',  ORDER => 'DESC' },
					   { FIELD => 'id',     ORDER => 'DESC' },
					   );

		  while (my $transaction = $transactions->Next) {
			my $attachments = $transaction->Attachments; 

			while (my $message = $attachments->Next) {
			  next unless $message->ContentType =~
					   m!^(text/html|text/plain|message|text$)!i;
		 
			  my $content = $message->Content;
			  $content =~ s/<.+?>//sg;  # strip HTML tags from text/html
			  next unless $content;

			  $content =~ s/##- Please type your reply above this line -##//g;
			  $content =~ s/&nbsp;/ /g;
			  $content =~ s/(^\s+$)+//mg;

			  next if $last_content eq $content;
			  $last_content = $content;

			  next if $user_date eq ($message->CreatorObj->id.$message->CreatedObj->ISO);
			  $user_date = $message->CreatorObj->id.$message->CreatedObj->ISO;

			  $email = '';
			  $name = '';
			  $email = $message->CreatorObj->EmailAddress;
			  $name = $message->CreatorObj->RealName;
			  if($name eq ''){
				  my ($name, $domain) = $email =~ /(.*)@(.*)/;
			  }
			  $name =~ s/(\.|_)/ /g;

		%data = (
			user => {
				name => $name,
				email => $email,
				verified => 1
			},
		);
		
		$data = encode_json(\%data);

		$response = $ua->post("$ZendeskURL/api/v2/users.json",
								 'Content' => $data,
								 'Content-Type' => 'application/json',
								 'Authorization' => "Basic $credentials");

			  $resolved_message .= "From: ";
			  $resolved_message .= $message->CreatorObj->RealName?$message->CreatorObj->RealName.' ('.$message->CreatorObj->EmailAddress.')' : $message->CreatorObj->EmailAddress;
			  $resolved_message .= "\n";
			  $resolved_message .= "At: ";
			  $resolved_message .= $message->CreatedObj->ISO;
			  $resolved_message .= "\n";
			  $resolved_message .= "\n";
			  $resolved_message .= "$content\n";
			  $resolved_message .= "\n";
			  $resolved_message .= "---";
			  $resolved_message .= "\n";
			}
		  }


		#--------------------------------------------------#

		my @custom_fields_data;

		"a" =~ /a/;

		# You can set as many custom fields as you need
		
		#if($self->TicketObj->FirstCustomFieldValue('DEMO') ne ''){
		#   push @custom_fields_data, ({id=>1111111111, value=>$self->TicketObj->FirstCustomFieldValue('DEMO')});
		#}

		#Read potential tags that Zendesk might have set
		$response = $ua->get("$ZendeskURL/api/v2/tickets/$ticket_id.json",
								 'Authorization' => "Basic $credentials");
		$response_json = decode_json($response->content());
		@options = @{ $response_json->{'ticket'}->{'tags'} };
		push @tags_data, @options;

		%data = (
			ticket => {
				comment => {
					body => $header.$res.$resolved_message,
					public => 0,
				},
				custom_fields => \@custom_fields_data,
				tags => \@tags_data,
			},
		);
		$url = "$ZendeskURL/api/v2/tickets/$ticket_id.json";
		$data = encode_json(\%data);

		$response = $ua->put($url,
								 'Content' => $data,
								 'Content-Type' => 'application/json',
								 'Authorization' => "Basic $credentials");

        return 1;
    }

    1;