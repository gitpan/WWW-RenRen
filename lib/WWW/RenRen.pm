package RenRen;

use LWP::UserAgent;
use HTTP::Request::Common;
use HTTP::Cookies;
use Encode;
use JSON;
use utf8;

BEGIN {
	our $VERSION = 0.02;
}

my $ua = undef;
my $cookie_jar = undef;
my $userid = undef;

my ($rtk, $requestToken) = (undef, undef);

sub new
{
	binmode (STDOUT, ':encoding(utf8)');

	$ua = LWP::UserAgent->new;
	$ua->timeout(3);

	$cookie_jar = HTTP::Cookies->new;
	$ua->cookie_jar ($cookie_jar);

	bless {}, shift;
}

sub get
{
	my $url = shift;
	my $resp = $ua->get ($url);
	$cookie_jar->extract_cookies ($resp);
	$resp->decoded_content;
}

sub post
{
	my ($url, $formRef) = @_;

	my $resp = $ua->post ($url, $formRef);
	$cookie_jar->extract_cookies ($resp);
	$resp->decoded_content;
}

sub login
{
	my (undef, $usr, $pw) = @_;
	my $loginURL = "http://www.renren.com/ajaxLogin/login";

	my %form = (
		'email' => $usr,
		'password' => $pw
	);

	my $json = from_json( post ($loginURL, \%form, { utf8  => 1 } ) );
	if ( $json->{'code'} eq 'true' )
	{
		# find rtk & requestToken
		for (split /\n/ , get($json->{'homeUrl'}))
		{
			if ($_ =~ /get_check:'([-0-9]+)',get_check_x:'([a-zA-Z0-9]+)'/)
			{
				$requestToken = $1;
				$rtk = $2;
			}
			elsif ( $_ =~ /XN.user.id = '([0-9]+)';/ )
			{ 
				$userid = $1;
				last;
			}
		}

		return 1;
	}
	else
	{
		print 'Unable to login: ', $json->{'failDescription'};
	}

	return 0;
}

sub postNewEntry
{
	my (undef, $title, $content, $pass, $cate) = @_;
	my $newEntryPostURL = "http://blog.renren.com/NewEntry.do";

	my %form = (
		body => $content,
		categoryid => defined $cate ? $cate : 0,
		blogControl => 99,
		passwordProtedted => 0,
		editBlogControl => 99,
		postFormid => -674374642,
		newLetterId => 0,
		blog_pic_id => undef,
		pic_path => undef,
		id => undef,
		relative_optype => saveDraft,
		isVip => undef,
		jf_vim_em => 'true',
		blackListChang => 'false',
		passWord => $pass,
		title => $title,
		requestToken => $requestToken,
		_rtk => $rtk,
	);

	my $json = from_json( post ($newEntryPostURL, \%form, { utf8  => 1 } ) );
	($json->{code} eq 0) ? 1 : 0;
}

sub postUpdatePhoto
{
	my $albumID = shift;

	my %form = (
		id => $albumID,
		title => "AUTORM",
		editUploadedPhotos => "false",
		requestToken => $requestToken,
		_rtk => $rtk,
	);

	my $photoEditURL = 'http://photo.renren.com/photo/' . $userid . '/album-' . $albumID . '/relatives/edit';
	print post ($photoEditURL, \%form);
}

sub uploadNewPhoto
{
	my (undef, $albumID, $photoref) = @_;

	my $photoPlainURL = "http://upload.renren.com/uploadservice.fcgi?pagetype=addPhotoPlain";
	my $photoEditURL = 'http://photo.renren.com/photo/' . $userid . '/album-' . $albumID . '/relatives/edit';
	
	my $i = 1;

	my @photos = (
		id => $albumID
	);

	for (@$photoref)
	{
		push @photos, "photo" . $i => [ $_ ];
		last if ++ $id > 5;
	}

	my $request = POST $photoPlainURL, 
		Content_Type => 'multipart/form-data', 
		Content => \@photos;

	my $resp = $ua->request ($request);
	if ( $resp->is_success && $resp->decoded_content =~ qq#<script># )
	{
		postUpdatePhoto ($albumID);

		return 1;
	}
	return 0;
}

sub createAlbum
{
	my (undef, $title, $pass) = @_;

	my $albumURL = "http://photo.renren.com/ajaxcreatealbum.do";
	my %form = (
		'title', $title,
		'control', 99,
		'password', $pass,
		'passwordProtected', defined ($pass) ? 'true' : 'false'
	);

	my $json = from_json( post ($albumURL, \%form, { utf8  => 1 } ) );
	return defined ($json->{'albumid'}) ? $json->{'albumid'} : "";
}

sub addThisFriend
{
	my (undef, $uid) = @_;
	
	my $requestFriendURL = "http://friend.renren.com/ajax_request_friend.do?from=sg_others_profile";
	my %form = (
		'id'  =>  $uid,
		'why' => '',
		'codeFlag'  =>  '0',
		'code'  =>  '',
		'requestToken'  =>  $requestToken,
		'_rtk'  =>  $rtk
	);

	my $json = from_json( post ($requestFriendURL, \%form), { utf8  => 1 } );
	if ( defined ($json->{'code'}) )
	{
		if ($json->{'code'} != 0)
		{
			print "Denied: ", $json->{'message'}, "\n";
		}
		return $json->{'code'};
	}

	return 0;
}

sub getCommonFriendsList
{
	my $rcdURL = "http://rcd.renren.com/cwf_nget_home";
	my %sent = ();

	for (split />/ , get($rcdURL) )
	{
		if ( $_ =~ /class="username" data-id="([0-9]+)"/ )
		{
			my $uid = $1;
			unless( defined ($sent{$uid}) )
			{
				$sent{$1}++;
			}
		}
	}

	return keys %sent;
}

sub getDoings
{
	my $doingsURL = 'http://www.renren.com/' . $userid . '#!//status/status?id=' . $userid . '&from=homeleft';
	print get ($doingsURL);
	for (split (/"/, get ($doingsURL)))
	{
		if ( $_ =~ /delMyDoing.*([0-9]+)/ )
		{
			print $1, "\n";
		}
	}
}

sub postNewStatus
{
	my (undef, $text) = @_;
	my $postStatusURL = 'http://shell.renren.com/' . $userid . '/status';
	
	my %form = (
		'requestToken', $requestToken,
		'_rtk', $rtk,
		'hostid', $userid,
		'content', decode ('utf8', $text),
		'channel', 'renren'
	);

	my $json = from_json( post ($postStatusURL, \%form, { utf8  => 1 } ) );
	if ( $json->{'code'} eq 0 )
	{
		# succeed
		return 1;
	}
	return 0;
}

sub delMyDoing
{
	my (undef, $id) = @_;

	my $deleteDoingURL = "http://status.renren.com/doing/deleteDoing.do";
	my %form = (
		'requestToken', $requestToken,
		'_rtk', $rtk,
		'id', $id
	);

	if ( post ($deleteDoingURL, \%form) =~ /succ/ )
	{
		return 1;
	}
	return 0;
}

1;

__END__

=head1 Name

 WWW::RenRen

=head1 DESCRIPTION 

 Simulate browser to complete all kinds of request of renren.com, 
 popular social website in China

 Note from author:
 Everything is transmitted as clear text, fuck renren.com, they
 never took my advice, so use it at your own risk.

=head1 SYNOPSIS

 use WWW::RenRen;

 my $rr = RenRen->new; 
 die unless $rr->login ('XX@yy.com', 'your_password'); # or use user id

=head2 new

 Create a new object and return,

 my $rr = RenRen->new;

=head2 login

 Login can be done with either your mail address or associated jabber ID, 
 nothing could be done before login.

 $rr->login ('XX@yy.com', 'password');

=head2 postNewStatus

 Post a new status, note: your perl script must be utf8 encoded.
 Optional encoding support coming soon.

 $rr->postNewStatus ('message_will_be_decoded_with_utf8');

=head2 createAlbum

 Create a new album, with password protection:

 $rr->createAlbum ('album_name', 'password');

 Or being open to all:

 $rr->createAlbum ('album_name');

 If succeed, return value would be the album id of newly created one.

=head2 delMyDoing

 Delete a posted status, 

 $rr->delMyDoing ('doing_id')

=head2 addThisFriend

 Add a friend to your list, user id must be number value

 $rr->addThisFriend ('user_id');

=head2 uploadNewPhoto

 Upload photos (at most 5) to a known album,

 $rr->uploadNewPhoto ('album_id', ['1.png', '2.png']);

=head2 postNewEntry

 Post a new blog entry, feature under testing

 $rr->postNewEntry ('title', 'content', 'password_optional', 'category_id_optional');
