#!/usr/bin/perl -w

use strict;
use warnings;

use DBI;

my %opts = ();
my $expr = '';

my $arg = '';
my $rtime = 0;
my $owntime = '';

#macros search default directories
my @macrodirs = ();
my @macrodir2 = ($ENV{'HOME'} . '/.iftime.pl/macros', '/etc/iftime.pl/macros', '/var/lib/iftime.pl/macros');
if(defined $ENV{'IFTIMEPL_MACRODIRS'})
{
	@macrodirs = split(':', $ENV{'IFTIMEPL_MACRODIRS'});
}
else
{
	foreach (@macrodir2)
	{
		push(@macrodirs, $_) if -d $_;
	}
}

#arguments parsing
while($arg = shift @ARGV)
{
	#read custom time/date
	if ($rtime == 1)
	{
		$rtime = 0;
		$owntime = $arg;
	}
	#parse options
	elsif ($arg =~ /^-[udprhtn]/)
	{
		#use utc time instead localtime
		$opts{'u'} = 1 if $arg =~ /u/;
		#print transfrormed sql expression
		$opts{'d'} = 1 if $arg =~ /d/;
		#print result instead of exit code
		$opts{'p'} = 1 if $arg =~ /p/;
		#print result instead of exit code
		$opts{'n'} = 1 if $arg =~ /n/;
		#read expression from file 
		$opts{'r'} = 1 if $arg =~ /r/;
		#print help message
		$opts{'h'} = 1 if $arg =~ /h/;
		#use custom time instead now
		if ($arg =~ /t/)
		{
			$rtime = 1;
		}
	}
	#parse unknown options
	elsif ($arg =~ /^-/)
	{
		die("Error: unknow argument '$arg'\n");
	}
	#read expression from ARGV or file
	else
	{
		$expr = defined $opts{'r'} ? file_get_contents($arg) : $arg;
	}
};

#print help message if expression is empty or option -h passed
if(defined $opts{'h'} || $expr eq '')
{
	help();
}

#create in-memory instance of sqlite3
my $db = DBI->connect("dbi:SQLite:dbname=:memory:","","") or die("Error: Can not create in-memory instance of sqlite! May be module DBD::SQLite is not installed?\n");

#switching between UTC and localtime
my $s1 = defined $opts{'u'} ? '' : ", 'localtime'";

#use now as time if not passed with -t
$owntime = 'now' if $owntime eq '';

#create sql for obtaining now in various formats
my $sql = "SELECT 'ok', strftime('%H:%M', '$owntime' $s1), date('$owntime' $s1), strftime('%Y-%m-%d %H:%M', '$owntime' $s1), strftime('%w', '$owntime' $s1), strftime('%m', '$owntime' $s1), strftime('%d', '$owntime' $s1), strftime('%Y', '$owntime' $s1)";

print STDERR "SQL_expr (retrieve current date/time): \n$sql\n" if defined $opts{'d'};

# @now - variuos subsets of current date and time 
# [0] - time, [1] - date, [2] - datetime, [3] - day of week, [4] - month, [5] - day of month, [6] - year
my @now = $db->selectrow_array($sql) or die("Error: '$sql' executing error!\n");

if(shift(@now) ne 'ok')
{
	die("Error: sql expresson '$sql' failed!\n" . $db->errstr . "\n");
}

if(@now != 7 || ! defined $now[0] || ! defined $now[1] || ! defined $now[2] || ! defined $now[3] || ! defined $now[4] || ! defined $now[5] || ! defined $now[6])
{
	die("Error: can not obtain current or overrided date/time!\n");
}

$expr =~ s/!/ NOT /g;
$expr =~ s/\&/ AND /g;
$expr =~ s/\|/ OR /g;

# recoding tables
my %week_tr = ('sun', 0, 'mon', 1, 'tue', 2, 'wed', 3, 'thu', 4, 'fri', 5, 'sat', 6, 'su', 0, 'mo', 1, 'tu', 2, 'we', 3, 'th', 4, 'fr', 5, 'sa', 6, 'workdays', 'IN (1, 2, 3, 4, 5)', 'weekend', ' IN (0, 6)');
my %month_tr = ('jan', '01', 'feb', '02', 'mar', '03', 'apr', '04', 'may', '05', 'jun', '06', 'jul', '07', 'aug', '08', 'sep', '09', 'oct', '10', 'nov', '11', 'dec', '12');

#array of functions for transformation date/time parts
my @uncode_f = (

	#recode time
	sub 
	{
		#no recode
		return($_[0]);
	}, 
	#recode date
	sub 
	{
		$arg = $_[0];
		#replaces dots with dashes
		$arg =~ s/\./-/g;
		#adding missing current year if year skipped
		$arg = "$now[6]-$arg" if $arg !~ /\d{4}/;
		return $arg;
	},
	#recode datetime
	sub 
	{
		$arg = $_[0];
		#replaces dots with dashes
		$arg =~ s/\./-/g;
		#adding missing current year if year skipped
		$arg = "$now[6]-$arg" if $arg !~ /\d{4}/;
		return $arg;
	},
	#recode day of week
	sub 
	{
		#translate day of week to number
		$arg = $week_tr{lc($_[0])};
		return($arg);
	},
	#recode month
	sub 
	{
		#translate month abbr to number
		$arg = $month_tr{lc($_[0])};
		return($arg);
	},
	#recode day of month
	sub
	{
		#no recode
		return($_[0]);
	},
	#recode year
	sub
	{
		#no recode
		return($_[0]);
	}
);

#process macros
$expr =~ s/\{(.*?)\}/unmacro($1)/ge;

#convert expression to sql
$expr =~ s/\[(.*?)\]/unrange($1)/ge;

$sql = "SELECT 'ok', $expr ;";
print STDERR "SQL_expr (calculate conditions):\n$sql\n" if defined $opts{'d'};
my @result = $db->selectrow_array($sql) or die("Error: '$sql' executing error!\n"  . $db->errstr . "\n");
if(shift(@result) ne 'ok')
{
	die("Error: sql expresson '$sql' failed!\n" . $db->errstr . "\n");
}
$db->disconnect;

if(defined $opts{'p'})
{
	print "$result[0]" . (defined $opts{'n'} ? '' : "\n");
	exit(0);
}
else
{
	exit(not $result[0]);
}

#################### subroutines below #######################

# replace {MACRO} with content of file MACRO.inc
sub unmacro
{
	my $arg = $_[0];
	die("Error: macro name must include only letters, numbers, and the underscore character!\n") if ! $arg =~ /^\w+$/;
	foreach my $dir (@macrodirs)
	{
		my $fn = "$dir/$arg.inc";
		return file_get_contents($fn) if -e $fn && -f $fn;
	}
	die("Error: macro file '$arg.inc' not found or not readable!\nsearched in " . join(':', @macrodirs) . "\n"); 
}

# covert expression short menemonics into valid sql expressions 
sub uncode
{
	my $arg = $_[0];
	my $qt = $_[1];
	return($uncode_f[$qt]->($arg));
}

# strip trailing spaces
sub trim
{
	my $str = $_[0];
	$str =~ s/^\s+|\s+$//g;
	return $str;
}

# convert arg1,arg2-arg3,... into sql expressions
sub unrange
{
	my $range = $_[0];
	my @result = ();
	my @rparts = split(',', $range);
	#print join(" | ", @rparts);
	my $tq = -1;
	my ($q1, $q2, $tq1, $tq2);
	foreach my $rpart (@rparts)
	{
		my @rparts2 = split('-', $rpart);
		if(@rparts2 == 2 && $rparts2[0] ne '' && $rparts2[1] ne '')
		{
			my $q1 = trim($rparts2[0]);
			my $q2 = trim($rparts2[1]);
			my $tq1 = qtype($q1, $tq);
			$tq = $tq1 if $tq < 0;
			my $tq2 = qtype($q2, $tq);
			$q1 = uncode($q1, $tq);
			$q2 = uncode($q2, $tq);
			my $qs = $tq < 3 ? "'" : '';
			die("Error: useing range keyword in range is not possible!\n") if $q1 =~ /^\s*IN\s+/ || $q2 =~ /^\s*IN\s+/;
			push(@result, "($qs$now[$tq]$qs BETWEEN $qs$q1$qs AND $qs$q2$qs)");
		}
		elsif(@rparts2 == 1 && $rparts2[0] ne '')
		{
			my $q1 = trim($rparts2[0]);
			my $tq1 = qtype($q1, $tq);
			$tq = $tq1 if $tq < 0;
			$q1 = uncode($q1, $tq);
			my $op = $q1 =~ /^\s*IN\s+/ ? '' : '=';
			my $qs = $tq < 3 ? "'" : '';
			push(@result, "($qs$now[$tq]$qs $op $qs$q1$qs)");
		}
		else
		{
			die("Error: found empty or malformed date/time subparameter '$rpart'!\n");
		}
	}
	return(@result > 1 ? '(' . join(' OR ', @result) . ')' : join(' OR ', @result));
}

# get condition type
sub qtype
{
	my $arg = lc($_[0]);
	my $qt = $_[1];
	#day of month
	return 5 if $arg =~ /^(\d{1,2})$/ && ($qt < 0 || $qt == 5);
	#year
	return 6 if $arg =~ /^(\d{4})$/ && ($qt < 0 || $qt == 6);
	#time
	return 0 if $arg =~ /^\d{2}:\d{2}$/ && $qt <= 0;
	#date
	return 1 if $arg =~ /^(\d{4}\.)?\d{2}\.\d{2}$/ && ($qt < 0 || $qt == 1);
	#datetime
	return 2 if $arg =~ /^(\d{4}\.)\d{2}\.\d{2}\s+\d{2}:\d{2}$/ && ($qt < 0 || $qt == 2);
	#days of week
	return 3 if $arg =~ /^(sun?|mon?|tue?|wed?|thu?|fri?|sat?|workdays|weekend)$/ && ($qt < 0 || $qt == 3);
	#month
	return 4 if $arg =~ /^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)$/ && ($qt < 0 || $qt == 4);
	die("Error: invalid (or not same type as previous) date parameter '$arg'\n");
}

# read file to sting
sub file_get_contents
{
    my @fcontent;
    open FILE,"$_[0]" or die "Error: can not open file $_[0]!\n";
    while(<FILE>)
    {
        push(@fcontent, $_);
    }
    close FILE;
    return(join("", @fcontent));
}

# print help message
sub help 
{ 
	my $mdirs = join(':', @macrodirs); 
	print <<'END_OF_HELP';
--------------------------------------------------------------------------------
usage: iftime.pl [-udprh] [-t custom_datetime] time_expression

options:

	-u 	- use UTC time instead of local time
	-d	- dump SQL expressions
	-p	- print result instead returning exit code
	-n	- omit \n from result if -p specified
	-r	- read time expression from file time_expression
	-t	- override current date/time with arbitrary value
	-h	- print help message

valid elements of time/date expression:

	|	- treats as logical OR
	&	- treats as logical END
	! 	- treats as logical NOT
	()	- parentheses for logical grouping 
	{arg}	- replaces with file arg.inc searched in macro directories
	[arg]	- group of time/date conditions of same type
		  can include multiple values separated by commas 
		  as well as ranges denoted by a dashes 
		  example: [arg1-arg2,arg3]

types of time/date conditions:

	HH:MM		 - time (hour and minute)
	mm.dd		 - date (month and day)
	yyyy.mm.dd	 - full date (year, month and day)
	yyyy.mm.dd HH:MM - full date and time
	yyyy		 - date (only year)
	mmm		 - date (only month, as Jun, Feb, Mar etc)
	dd		 - date (only day)
	www		 - date (day of week, as Sun, Mon, Tue etc,
			   and also Workdays and Weekend)

directories by default in which macro files will be searched:
~/.iftime.pl/macros:/etc/iftime.pl/macros:/var/lib/iftime.pl/macros

examples:

./iftime.pl '[weekend] | ![08:00-20:00]' && echo 'relaх time' || echo 'worktime'
./iftime.pl -up -t '2022-01-01 10:00' '[09:00-12:00] & [Jan] & ![2-30] & [2022]'
--------------------------------------------------------------------------------

END_OF_HELP
; exit(1);
}
