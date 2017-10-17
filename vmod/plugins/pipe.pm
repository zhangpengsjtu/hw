#!/usr/bin/env perl

package pipe;
use strict;
use warnings FATAL => qw(all);

use Carp qw(croak);
use Getopt::Long qw(GetOptions);
use Text::ParseWords qw(shellwords);

=head1 PIPE

  &eperl::pipe("[-is|os] [-wid <n>]");
    
  Required Inputs:
    NONE

  Optional Inputs:
    -is  : input skid buffer            
    -os  : output skid buffer           

    -wid <n> : width of data

  Example: 
    A pipe with input skip, 18 bits data
    &eperl::pipe("-is -wid 18");

  Behavior:
    ----------
    Basic Pipe
    ----------
    The pipe function generates a single pipe stage with bubble collapsing(bc).
    Input skid(is) adds comb logic on vi side, while make ro timing clean
    On contrast output skid(os) adds comb logic on vo side, while make ri timing clean
        
    BASIC        | SKID
                 |
    pipe -bc     |   -is                            -os                            
    ------------ |   -----------------------------  -----------------------------
     di,vi,ro    |     di,vi              ro          di,vi              ro        
      v     ^    |       v                ^             v                ^         
      |     |    |     __|  __            |            _|________________|_        
     _|_    |    |    | _|_|_ |           |           |        pipe        |       
    |>__|   |    |    | \___/-|------     |           |____________________|       
      | - >(*)   |    |  _|_  | |  _|_   _|_          __|  __            |         
      |     |    |    | |>__| | | |>__| |>__|        | _|_|_ |           |         
      |     |    |    |__ |___| |   |     |          | \___/-|------     |         
      |     |    |      _|_|_   |   ------|          |  _|_  | |  _|_   _|_        
      v     ^    |      \___/---          |          | |>__| | | |>__| |>__|       
     do,vo,ri    |       _|_______________|_         |__ |___| |   |     |         
                 |      |        pipe       |          _|_|_   |   ------|         
                 |      |___________________|          \___/---          |         
                 |        |               |              |               |         
                 |        v               ^              v               ^         
                 |     do,v               ri           do,vo             ri        

=cut

use base ("Exporter");
our @EXPORT = qw(pipe);

my @code = ();
my $clk = "clk";
my $rst = "rst";
my $indent= 0;

sub pipe {
    my $args = shift;
    @ARGV = shellwords($args);
    
    #================================
    # OPTIONS
    #================================
    
    my $prefix = "pipe";
    my $wid = 1;
    my $is;
    my $os;
    GetOptions (
               'prefix=s'  => \$prefix,
               'is'    => \$is,
               'os'    => \$os,
               'wid=s' => \$wid,
               'clk=s' => \$clk,
               'rst=s' => \$rst,
               'indent=s' => \$indent,
               )  or die "Unrecognized options @ARGV";
    
    #================================
    # VARIABLE
    #================================
    my $vi = $prefix."_vi";
    my $ro = $prefix."_ro";
    my $di = $prefix."_di";
    my $vo = $prefix."_vo";
    my $ri = $prefix."_ri";
    my $do = $prefix."_do";


    my $msb = eval($wid-1);
    my $range = "$msb:0";
    
    my $DI = $di."[$range]";
    my $DO = $do."[$range]";
    my $INDENT = " "x$indent;

    #================================
    # HEAD
    #================================

    # is
    ($vi,$di,$ro) = _skid($vi,$di,$ro,$range) if $is;

    # pipe
    ($vi,$di,$ro) = _pipe($vi,$di,$ro,$range);

    # os
    ($vi,$di,$ro) = _skid($vi,$di,$ro,$range) if $os;


    #================================
    # TAIL
    #================================
    push @code, "${INDENT}assign $ro = $ri;";
    push @code, "${INDENT}assign $vo = $vi;";
    push @code, "${INDENT}assign $do = $di;";
    
    my $code = join("\n",@code);
    $code .= "\n";

    #================================
    # PRINT OUT
    #================================
    print $code;
}

sub _pipe {
    my $vi = shift;
    my $di = shift;
    my $ro = shift;
    my $range = shift;

    my $INDENT = " "x$indent;

    my $vo = "pipe_".$vi;
    my $do = "pipe_".$di;
    my $ri = "pipe_".$ro;
    
    my $DI = $di."[$range]";
    my $DO = $do."[$range]";
    
    # READY
    push @code, "// PIPE READY";
    push @code, "${INDENT}assign $ro = $ri || !$vo;";
    push @code, "";
    # VALID
    push @code, "// PIPE VALID";
    push @code, "${INDENT}always (posedge $clk or negedge $rst) begin";
    push @code, "${INDENT}    if (!$rst) begin";
    push @code, "${INDENT}        $vo <= 1'b0;";
    push @code, "${INDENT}    end else begin";
    push @code, "${INDENT}        if ($ro) begin";
    push @code, "${INDENT}            $vo <= $vi;";
    push @code, "${INDENT}        end";
    push @code, "${INDENT}    end";
    push @code, "${INDENT}end";
    push @code, "";
    # DATA
    push @code, "// PIPE DATA";
    push @code, "${INDENT}always (posedge $clk) begin";
    push @code, "${INDENT}    if ($ro && $vi) begin";
    push @code, "${INDENT}        $DO <= $DI;";
    push @code, "${INDENT}    end";
    push @code, "${INDENT}end";
    push @code, "\n";

    return ($vo,$do,$ri);
}

sub _skid {
    my $vi = shift;
    my $di = shift;
    my $ro = shift;
    my $range = shift;
    
    my $INDENT = " "x$indent;

    my $vs = "skid_flop_".$vi;
    my $ds = "skid_flop_".$di;
    my $rs = "skid_flop_".$ro;

    my $vo = "skid_".$vi;
    my $do = "skid_".$di;
    my $ri = "skid_".$ro;
    
    my $DI = $di."[$range]";
    my $DS = $ds."[$range]";
    my $DO = $do."[$range]";
    
    
    # READY
    push @code, "// SKID READY";
    push @code, "${INDENT}always (posedge $clk or negedge $rst) begin";
    push @code, "${INDENT}   if (!$rst) begin";
    push @code, "${INDENT}       $ro <= 1'b1;";
    push @code, "${INDENT}       $rs <= 1'b1;";
    push @code, "${INDENT}   end else begin";
    push @code, "${INDENT}       $ro <= $ri;";
    push @code, "${INDENT}       $rs <= $ri;";
    push @code, "${INDENT}   end";
    push @code, "${INDENT}end";
    push @code, "";

    # VALID
    push @code, "// SKID VALID";
    push @code, "${INDENT}always (posedge $clk or negedge $rst) begin";
    push @code, "${INDENT}    if (!$rst) begin";
    push @code, "${INDENT}        $vs <= 1'b0;";
    push @code, "${INDENT}    end else begin";
    push @code, "${INDENT}        if ($rs) begin";
    push @code, "${INDENT}            $vs <= $vi;";
    push @code, "${INDENT}        end";
    push @code, "${INDENT}   end";
    push @code, "${INDENT}end";
    push @code, "${INDENT}assign $vo = ($rs) ? $vi : $vs;";
    push @code, "";
    
    # DATA
    push @code, "// SKID DATA";
    push @code, "${INDENT}always (posedge $clk) begin";
    push @code, "${INDENT}    if ($rs & $vi) begin";
    push @code, "${INDENT}        $DS <= $DI;";
    push @code, "${INDENT}    end";
    push @code, "${INDENT}end";
    push @code, "${INDENT}assign $DO = ($rs) ? $DI : $DS;";
    push @code, "\n";

    return ($vo,$do,$ri);
}

1;
