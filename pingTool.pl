#!/usr/bin/perl
###########################################################################################################
#
#      Ping Test Tool 
#
# =========================================================================================================
#
#       2020/01 Created Ver 2.0 Nakamura Satoshi
#
###########################################################################################################

use strict;
use warnings;
use Time::Local;
use File::Path 'mkpath';
no strict "refs";

$|++;

# Set Default Ping Param
my $INTERVAL    ="0.5";
my $TIMEOUT     ="1";
my $SIZE	="500";
my $DFBIT       ="-M do";
my $PROM;

# Global value & array
my @arrayHost;		# array for ping destination
my %hashComment;	# hash for ip comment
my @arrayPID1;		# array for ping procces ID for "testPing" 
my @arrayResult;	# ping result file for calc
my $ip;			# ping destination IP
my $comment;		# commnet for ping destination IP
my $dir = `date "+%Y_%m_%d"`;
my @tail_PID;		# ping result file for calc
my $src = "PC";
my $testName = "failover";
my @arrayHistory;	# array for 
my $no;			# ping No.	

# INIT
chomp($dir);
unless(-d $dir){ mkdir $dir; }

# open "host.txt"
open(HOST,"host.txt") or die"\nERROR : Can't open host.txt \n\n";

# read IPaddress from host.txt
while(<HOST>){

	($ip,$comment) = split(/\s+/, $_);

	#Determine IP address and store in array
	if($ip=~/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/){
		chomp($ip);
		chomp($comment);
		push(@arrayHost,$ip);
		$hashComment{$ip} = $comment;
	}
}
close(HOST);

if(!@arrayHost){
	die "\nERROR :IPaddress not described in host.txt\n\n";
}

###########
#
#  CLI

# ping flag
my $flgPing = "0";

# CLI init
print " ----------------\n";
print "  Start!!\n";
print " ----------------\n";
&help;
&printProm;

# CLI
while( defined(my $line=<STDIN>) ){

	# Record Command History
	if($line =~/\w.*/){
		push(@arrayHistory, "  $line");
	}

	chomp($line);

	# EXIT
	if( $line eq "exit" ){
		if( $flgPing eq "1" ){
			&killPIDs(\@arrayPID1);
			&killPIDs(\@tail_PID);
			&delFile(\@arrayHost);

			&printProm;
			print "\n";

			$flgPing = "0";
		}
		last;

	# SET PING SOURCE 
	}elsif( $line =~/set src (.*)/ ){

		$src = $1;
		print "\n  Set Ping Source name ($1)\n\n";

		&printProm;


	# SET NAME 
	}elsif( $line =~/set name (.*)/ ){

		$testName = $1;
		print "\n  Set test file name ($1)\n\n";

		&printProm;


	# SET INTERVAL 
	}elsif( $line =~/set interval (\d+\.\d+)/ ){

		if ($1 <= 0.2){
			print "\n  !!WARNING!!\n";
			print "    Execution in less than 0.2 sec of PING requires execution with ROOT permission! \n";
		}

		$INTERVAL = $1;
		print "\n  Set ping Interval ($1 sec)\n\n";

		&printProm;

	# SET DataSize 
	}elsif( $line =~/set ds (\d{2,4})/ ){

		$SIZE = $1;
		print "\n  Set ping Data size ($1 sec)\n\n";

		&printProm;

	# START PING      
	}elsif( $line =~/^p(\s+)(.+)$/ ){

		if( $flgPing eq "0" ){

			$no = $2;

			# mkdir for evidence
			my $log_dir = "$dir/$no";
			unless(-d $log_dir){ mkpath $log_dir; }

			# mkdir for raw ping result
			my $raw_dir = "$log_dir/raw";
			unless(-d $raw_dir){ mkpath $raw_dir; }

			# Ping Start Message
			print "\n[Test No.$no]\n";
			print " ---------------------------------------------------\n";
			print "  Ping Start!! \n";
			print "   [ Interval  ] : ($INTERVAL) sec\n";
			print "   [ Timeout   ] : ($TIMEOUT) sec\n";
			print "   [ Data size ] : ($SIZE) byte\n";
			print " ---------------------------------------------------\n";

			$flgPing = "1";
			$PROM = "$no";

			# check Target Host health 
			&checkAlive(\@arrayHost);

			# Exec Ping
			my ($ref_PID,$ref_Result) = &testPing(\@arrayHost,$no);
		
			print "\n";
			&printProm; 
	
			# Get PingPIDs and ResultFileList (de refarence)
			@arrayPID1 = @{$ref_PID};
			@arrayResult = @{$ref_Result};


			# loss Check
			foreach (0..$#arrayResult){

				my $file = $arrayResult[$_];

				# fork:PARENT
				if(my $p = fork){
					push(@tail_PID, $p);

				# fork : Child
				}elsif( defined $p ){

			 		my @file = split(/_+/,$file );
					my $host = $file[0];
					my $evidence = "$testName\_$no\_$src\_to\_$file";

					open( $evidence, ">$dir/$no/$evidence") or die "Can't open file $evidence:$!";
					(select($evidence), $|=1);

					open(my $fh,"tail -f $dir/$no/raw/$file |") or die "Can't open Result";
					(select($fh), $|=1);

					&lossCheck("live",$fh,$evidence,$host);

					close($fh);
					close($evidence);
					exit;
				}
			}
		}else{
			print "Ping is already running\n\n";
			&printProm;
		}	
 
	# STOP PING      
	}elsif( $line eq "stop"){

		$PROM = "";
		if( $flgPing eq "1" ){
			# kill process
			&killPIDs(\@arrayPID1); # Stop Ping
			&killPIDs(\@tail_PID);  # Stop File Streaming
			&delFile(\@arrayHost);  # Delete temporary file

			# wait child PIDs
			foreach(@tail_PID){ my $pid = waitpid $_,0 }

			@tail_PID = ();	

			# Set Flag
			$flgPing = "0";

			print "\n Stop Ping running!\n";
			print "\n";
			&printProm;

		}else{
			print "Ping is not running\n\n";
			&printProm;
		}
		

	# SHOW RESULT (show packet loss) 
	}elsif( $line =~/^show(\s+)log(\s+)(.+)$/){

		my $resNo = $3;
		my @files;

		# 
		if($resNo eq "all"){ 
			# show Todays All Test Result
			@files = glob "$dir/*/raw/*.txt";

		}elsif($no eq $resNo){
			# show Todays Specific No. Test Result
			@files = glob "$dir/$resNo/raw/*.txt";

		}else{
			print "Test No. is  Not specified or Nothing !!\n\n";
			#&printProm;
		}
		
		while (<@files>){

			open(my $file,"cat $_ |") or die "Can't open Result";


			# Print Header
			my @dirs = split(/\//,$_);
			print "__________________________________________________________________________\n";
			print "$dir/$resNo/$src to $dirs[$#dirs]\n";
			print "==========================================================================\n";
			print "[loss start]   [loss end] 	[seq]	[D_loss]	[D_time]\n";
			my $cc = &lossCheck("result",$file);
			print "__________________________________________________________________________\n";
			print "TotalCount:$cc,\n\n";
			close($file);
		}
		&printProm;

	# Enter (print prompt) 
	}elsif( $line eq ""){
		&printProm;

	# HELP (show usage) 
	}elsif( $line eq "help"){
		&help;
		&printProm;

	# Command history  
	}elsif( $line eq "history"){
		my $i = 1;	#index
		foreach(@arrayHistory){
			print " $i $_";
			$i++;
		}
		&printProm;

	# Other (call OS command) 
	}else{
		system($line);
		&printProm;
	}
}


################################################ 
#
# HIERARCHY 2 SUBROUTINE
#

sub printProm{ 
	if ($PROM) {
		 print "$0 ($PROM) # ";
	}else{
		 print "$0> ";
	} 
}

# subroutine: check Alive ----------------------
# 
#  check the health of target host  
#   argument1 :IP address list (array)
# ---------------------------------------------- 
sub checkAlive {

	my @arrayHost_local = @{$_[0]};

	foreach my $host (@arrayHost_local){

		# Online Check
		my $online = system("ping -c 3 -i 0.2 -W 1 $host > /dev/null");
		if($online == 0){
			# print OK Message
			print "  Ping Start OK ($host) :$hashComment{$host}\n";
		}else{
			print "  Ping Start *NG* ($host) :$hashComment{$host}\n";
		}
	}
}


# subroutine: test Ping ------------------------
# 
#  exec linux ping command shell 
#   ____________________________________________ 
#   argument1 :IP address list (array)
#   argument2 :Test No. string (value)
#   return1   :ping process IDs (array)
#   return2   :ping result fiels (array)
# ---------------------------------------------- 
sub testPing{ 

	my @arrayPID_local; 
	my @arrayResult_local;

	# get hostlist & Test_No.
	my @arrayHost_local = @{$_[0]};
	my $no = $_[1];

	# set File Name
	my $time = `date "+%Hh%Mm%Ss"`;
	chomp($time);

	foreach my $ip (@arrayHost_local){

		# rename IP to Comment
		my $host = &renameHost($ip);

		# set result filename
		my $file = "$host\__$time.txt";

 		# exec Ping Shell 
 		my $cmd = "
 			ping -n -O -W 1 -i $INTERVAL -s $SIZE $ip $DFBIT 2>> $ip.error | 
                        while read pi 2>> $ip.error ;
			do echo \"\$(date '+%Y/%m/%d %H:%M:%S.%3N') \$pi\" 2>> $ip.error ;
			done > $dir/$no/raw/$file & 
 			jobs -l > $ip.pid 2>> $ip.error";
		my $return = system($cmd);

		# error handling
		my @error  =`cat $ip.error`;
		if( $return > 0 or @error ){
			print "NG ($return)\n";
			print "error (@error)\n";
		}
		
 		# get ping PID
 		open my $job_pid, "cat $ip.pid |";
 		my @job_pid = <$job_pid>; 
 		close $job_pid;

		# create PID array for kill proc
 		my @pid = split(/\s/, $job_pid[0]);
		if(!$pid[2]){
			print "ERROR :get ping PID is fail( ping to $ip)\n\n";
		}else{
			push(@arrayPID_local, $pid[2]);
		}

		# create result file array for calc 
		push(@arrayResult_local, $file);
		$file =();
	}
	# return
	return(\@arrayPID_local,\@arrayResult_local);
}


################################################ 
#                                              
# HIERARCHY 2 SUBROUTINE                   
#                                     

# subroutine: Kill PIDs ------------------------
# 
#  kill ping processes & delte temporary files 
#   argument1 :kill process ID list (array)
#   argument2 :ip address list (array)
# ---------------------------------------------- 
sub killPIDs {

	# dereference 
	my @arrayPID_local  = @{$_[0]};

	# kill process
	foreach my $pid (@arrayPID_local){

		#check child process
		my $cpid = `ps --ppid $pid --no-heading | awk '{ print \$1 }'`;
		chomp($cpid);

		# kill childprocess
		if($cpid){ 
			kill(9,$cpid);
			#print "kill Child PID : ($cpid)\n";
		}
		# kill process
		kill(9,$pid);
		#print "kill PID : ($pid)\n";
	}
}


sub delFile {

	# dereference 
	my @arrayHost_local = @{$_[0]};

 	# delete temporaly file
	foreach my $host (@arrayHost_local){
		unlink "$host.pid";
		unlink "$host.error";
	}
}


# subroutine: help -----------------------------
# 
#  kill ping processes & delte temporary files 
# ---------------------------------------------- 
sub help {

        print <<HELP;


 [Pingテストツール]


 １．機能

　・複数の宛先へのPing同時実行
　・エビデンス（Ping実行結果）の自動保存
　・障害時のPing断時間の算出


 ２．使い方

　(1) ツールの起動

    # $0  

    -(実行例)------------------------------

     \$ $0 
     ----------------
      Start!!
     ----------------
     ～中略～ 

    $0>
    ---------------------------------------


　(2) 以下のコマンドでやりたいことを実行する
   
    ・Pingの実行(host.txt に登録された IP に Ping を開始する)
      ------------------------------------
      $0> p <テスト識別名>
      ------------------------------------

    ・ Ping を停止
      ------------------------------------
      $0> stop
      ------------------------------------
 
    ・いままでの Ping 断時間を表示。allを指定した場合は当日の結果すべてを表示する。
      ------------------------------------
      $0> show log <テスト識別名|all>
      ------------------------------------

    ・ 実行結果ファイル名に付加されるテスト種別名を変更する。（初期値は"$testName"）
      ------------------------------------
      $0> set name <テスト種別名>
      ------------------------------------
      例) 以下のだとfailoverの箇所が変わります。
      failover_test1_PC_to_localhost__15h18m29s.txt
      ^^^^^^^^ 

    ・ 実行結果ファイル名に付加される送信元名を変更する。（初期値は"$src"）
      ------------------------------------
      $0> set src <送信元名>
      ------------------------------------
      例) 以下のだとPCの箇所が変わります。
      failover_test1_PC_to_localhost__15h18m29s.txt
                     ^^ 

    ・Ping の実行間隔を設定。（初期値は"$INTERVAL"秒）
      ------------------------------------
      $0> set interval <秒数>
      ------------------------------------

    ・Ping のデータサイズを設定。（初期値は"$SIZE"バイト）
      ------------------------------------
      $0> set ds <秒数>
      ------------------------------------

    ・ツールの終了
      ------------------------------------
      $0> exit
      ------------------------------------



HELP
} 


#現在時刻を取得するサブルーチン
sub getTime{
	use Time::Local;
	my @date1 = `date "+%Y/%m/%d %H:%M:%S.%3N"`;
        chomp($date1[0]);
        return $date1[0];
}

#時間差を計算するサブルーチン
sub time_calc{
	my ($Sy,$Sm,$Sd,$Sh,$Smin,$Ssec,$Sms) =
	 $_[0] =~/^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d{3})$/;

	my ($Ey,$Em,$Ed,$Eh,$Emin,$Esec,$Ems) =
	 $_[1] =~/^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2}):(\d{2})\.(\d{3})$/;

	my $b_time = timelocal($Ssec, $Smin, $Sh, $Sd, $Sm-1, $Sy-1900);
	my $e_time = timelocal($Esec, $Emin, $Eh, $Ed, $Em-1, $Ey-1900);

	my $diff   = "$e_time.$Ems" - "$b_time.$Sms";
	return sprintf("%.3f",$diff);
}


# convert time (hh:mm:ss.sss) to (hh:mm:ss.s)
sub time_conv{

	my ($h,$min,$sec,$ms) = $_[0] =~/^(\d{2}):(\d{2}):(\d{2})\.(\d{3})$/;
	$sec =  sprintf("%.1f","$sec.$ms");
	return "$h:$min:$sec";
}


sub lossCheck{

	my $type     = $_[0];
	my $fh       = $_[1];
	my $evidence = $_[2];
	my $host     = $_[3];

	my $count = 0;
	my $seq1  = 0;
	my $seq2  = 0;
	my $loss_start_time = &getTime;
	my $NGmsg;
	my $status = "OK";

	while(<$fh>){

		# Skip First Line
		if( $count == 0 ){ $count++;  next; }

		# Check OK Message
		if( $_=~/(\d{4}\/\d{2}\/\d{2}) (\d{2}:\d{2}:\d{2}\.\d{3}) (\d{2,5}) bytes from (\d+\.\d+\.\d+\.\d+): icmp_seq=(\d+) ttl=(\d+) time=(\d+)?(\.\d+)? ms/ ){ 

			$status ="OK";

			# case PING OK	
			if( $evidence ){ print $evidence "[ OK ] $_"; }

		# case other(=NG) Message
		}else{
			# case OK->NG	
			if( $status eq "OK" and $type eq "live" ){
				$host = &renameHost($host);
				print STDOUT " Ping OK -> NG ($host) \n";
			}

			# case NG
			if( $evidence ){ print $evidence " -> [ NG ] $_"; }
			$status ="NG";
			$count++;
			next;
		}

		######
		#
		# Processing on Ping NG->OK
		#  1. Count packet loss from ping sequence No.
		#  2. Calculate down time
		#  3. Print NG message to log_file & screen
		#

		# (1)
		$seq1 = $5;				# get seq_No.
		if( $seq2 == 65535 ){ $seq2 = -1; }	# case icmp_count reset
		my $dlt_seq  = $seq1-$seq2;		# check loss (seq_No. delta)


		# (2)
		if($dlt_seq != 1 ){
			my $loss_end_time = "$1 $2";
			my $delta_time = sprintf("%.1f",&time_calc($loss_start_time,$loss_end_time));

			# (3)
			my ($d,$t) = split(/\s/,$loss_start_time);
			#my $time1 = &time_conv($t); # loss start
			#my $time2 = &time_conv($2); # loss end
			if( $type eq "live" ){
				$host = &renameHost($host);
				$NGmsg = "[ $t - $2 ]:($host)	loss($dlt_seq)		down_time($delta_time sec)";

			}elsif( $type eq "result"){
				$NGmsg = "$t - $2	($seq2)	($dlt_seq)		($delta_time sec)";
			}

			if( $evidence ){
				print $evidence " __________________________________________________________________________\n";
				print $evidence "$NGmsg\n\n";
			}
			print STDOUT "$NGmsg\n";
		}
		$loss_start_time = "$1 $2";
		$seq2 = $seq1;
		$count++;
	}
	return $count;
}

sub timeout{
	print "timeout\n";
}


sub renameHost{

	# get ip_address 
	my $ip = $_[0];

	# rename 
	if($hashComment{$ip}){ 
		return $hashComment{$ip};
	}else{
		return $ip;
	}
}


