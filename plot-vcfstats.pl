#!/usr/bin/env perl
#
#   Copyright (C) 2012-2014 Genome Research Ltd.
#
#   Author: Petr Danecek <pd3@sanger.ac.uk>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# Dependencies:
#   - matplotlib
#       http://matplotlib.sourceforge.net
#   - LaTex/xcolor.sty
#       Download .sty.gz LaTeX class style from http://www.ukern.de/tex/xcolor.html,
#       unpack and install system-wide or place elsewhere and make available by
#       setting the TEXINPUTS environment variable (note the colon)
#           export TEXINPUTS=some/dir:
#       The list of the recognised path can be obtained from `kpsepath tex`
#
#

use strict;
use warnings;
use Carp;
use Storable qw(dclone);

my $opts = parse_params();
parse_vcfstats($opts);
merge_vcfstats($opts) if @{$$opts{vcfstats}} > 1;

chdir($$opts{dir});
if ( $$opts{make_plots} )
{
    init_plots($opts);
    plot_venn_bars($opts);
    plot_counts_by_AF($opts);
    plot_overlap_by_AF($opts);
    plot_concordance_by_AF($opts);
    plot_concordance_by_sample($opts);
    for my $id (file_ids($opts))
    {
        plot_tstv_by_AF($opts,$id);
        plot_tstv_by_QUAL($opts,$id);
        plot_indel_distribution($opts,$id);
        plot_substitutions($opts,$id);
        plot_per_sample_stats($opts,$id);
        plot_DP($opts,$id);
        plot_hwe($opts,$id);
    }
    plot($opts);
}
create_pdf($opts) unless !$$opts{make_pdf};

exit;

#--------------------------------

sub usage
{
    print STDERR
        "About: Plots output of \"bcftools stats\"\n",
        "Usage: plot-vcfstats [OPTIONS] file.chk ...\n",
        "       plot-vcfstats -p outdir/ file.chk ...\n",
        "Options:\n",
        "   -m, --merge                         Merge vcfstats files to STDOUT, skip plotting.\n",
        "   -p, --prefix <dir>                  Output directory.\n",
        "   -P, --no-PDF                        Skip the PDF creation step.\n",
        "   -r, --rasterize                     Rasterize PDF images for fast rendering.\n",
        "   -s, --sample-names                  Use sample names for xticks rather than numeric IDs.\n",
        "   -t, --title <string>                Identify files by these titles in plots. Can be given multiple times.\n",
        "   -T, --main-title <string>           Main title for the PDF.\n",
        "   -h, -?, --help                      This help message.\n",
        "\n";
}


sub error
{
    my (@msg) = @_;
    if ( scalar @msg ) { confess @msg; }
    usage();
    exit 1;
}


sub parse_params
{
    $0 =~ s{^.+/}{};
    my $opts =
    {
        pdf_plots  => 1,
        use_sample_names => 0,
        verbose    => 1,
        make_pdf   => 1,
        make_plots => 1,
        merge      => 0,
        args       => join(' ',$0,@ARGV),
        img_width  => 11/2.54,
        img_height => 10/2.54,
        id2col     => [ 'orange', 'red', 'darkgreen' ],
        tex =>
        {
            slide3v => { height1 => '7cm', height2 => '7cm',  height3 => '4.5cm' },
            slide3h => { width1  => '15cm', width2 => '10cm', width3 => '8cm' },
        },

        # for file version sanity check
        sections =>
        [
            {
                id=>'ID',
                header=>'Definition of sets',
                exp=>"# ID\t[2]id\t[3]tab-separated file names"
            },
            {
                id=>'SN',
                header=>'SN, Summary numbers',
                exp=>"# SN\t[2]id\t[3]key\t[4]value"
            },
            {
                id=>'TSTV',
                header=>'# TSTV, transition/transversions:',
                exp=>"# TSTV\t[2]id\t[3]ts\t[4]tv\t[5]ts/tv\t[6]ts (1st ALT)\t[7]tv (1st ALT)\t[8]ts/tv (1st ALT)"
            },
            {
                id=>'SiS',
                header=>'Sis, Singleton stats',
                exp=>"# SiS\t[2]id\t[3]allele count\t[4]number of SNPs\t[5]number of transitions\t[6]number of transversions\t[7]number of indels\t[8]repeat-consistent\t[9]repeat-inconsistent\t[10]not applicable"
            },
            {
                id=>'AF',
                header=>'AF, Stats by non-reference allele frequency',
                exp=>"# AF\t[2]id\t[3]allele frequency\t[4]number of SNPs\t[5]number of transitions\t[6]number of transversions\t[7]number of indels\t[8]repeat-consistent\t[9]repeat-inconsistent\t[10]not applicable"
            },
            {
                id=>'IDD',
                header=>'IDD, InDel distribution',
                exp=>"# IDD\t[2]id\t[3]length (deletions negative)\t[4]count"
            },
            {
                id=>'ST',
                header=>'ST, Substitution types',
                exp=>"# ST\t[2]id\t[3]type\t[4]count"
            },
            {
                id=>'GCsAF',
                header=>'GCsAF, Genotype concordance by non-reference allele frequency (SNPs)',
                exp=>"# GCsAF\t[2]id\t[3]allele frequency\t[4]RR Hom matches\t[5]RA Het matches\t[6]AA Hom matches\t[7]RR Hom mismatches\t[8]RA Het mismatches\t[9]AA Hom mismatches\t[10]dosage r-squared\t[11]number of genotypes"
            },
            {
                id=>'GCiAF',
                header=>'GCiAF, Genotype concordance by non-reference allele frequency (indels)',
                exp=>"# GCiAF\t[2]id\t[3]allele frequency\t[4]RR Hom matches\t[5]RA Het matches\t[6]AA Hom matches\t[7]RR Hom mismatches\t[8]RA Het mismatches\t[9]AA Hom mismatches\t[10]dosage r-squared\t[11]number of genotypes"
            },
            {
                id=>'NRDs',
                header=>'Non-Reference Discordance (NRD), SNPs',
                exp=>"# NRDs\t[2]id\t[3]NRD\t[4]Ref/Ref discordance\t[5]Ref/Alt discordance\t[6]Alt/Alt discordance"
            },
            {
                id=>'NRDi',
                header=>'Non-Reference Discordance (NRD), indels',
                exp=>"# NRDi\t[2]id\t[3]NRD\t[4]Ref/Ref discordance\t[5]Ref/Alt discordance\t[6]Alt/Alt discordance"
            },
            {
                id=>'GCsS',
                header=>'GCsS, Genotype concordance by sample (SNPs)',
                exp=>"# GCsS\t[2]id\t[3]sample\t[4]non-reference discordance rate\t[5]RR Hom matches\t[6]RA Het matches\t[7]AA Hom matches\t[8]RR Hom mismatches\t[9]RA Het mismatches\t[10]AA Hom mismatches\t[11]dosage r-squared"
            },
            {
                id=>'GCiS',
                header=>'GCiS, Genotype concordance by sample (indels)',
                exp=>"# GCiS\t[2]id\t[3]sample\t[4]non-reference discordance rate\t[5]RR Hom matches\t[6]RA Het matches\t[7]AA Hom matches\t[8]RR Hom mismatches\t[9]RA Het mismatches\t[10]AA Hom mismatches\t[11]dosage r-squared"
            },
            {
                id=>'PSC',
                header=>'PSC, Per-sample counts',
                exp=>"# PSC\t[2]id\t[3]sample\t[4]nRefHom\t[5]nNonRefHom\t[6]nHets\t[7]nTransitions\t[8]nTransversions\t[9]nIndels\t[10]average depth\t[11]nSingletons"
            },
            {
                id=>'PSI',
                header=>'PSI, Per-sample Indels',
                exp=>"# PSI\t[2]id\t[3]sample\t[4]in-frame\t[5]out-frame\t[6]not applicable\t[7]out/(in+out) ratio\t[8]nHets\t[9]nAA"
            },
            {
                id=>'DP',
                header=>'DP, Depth distribution',
                exp=>"# DP\t[2]id\t[3]bin\t[4]number of genotypes\t[5]fraction of genotypes (%)\t[6]number of sites\t[7]fraction of sites (%)"
            },
            {
                id=>'FS',
                header=>'FS, Indel frameshifts',
                exp=>"# FS\t[2]id\t[3]in-frame\t[4]out-frame\t[5]not applicable\t[6]out/(in+out) ratio\t[7]in-frame (1st ALT)\t[8]out-frame (1st ALT)\t[9]not applicable (1st ALT)\t[10]out/(in+out) ratio (1st ALT)"
            },
            {
                id=>'ICS',
                header=>'ICS, Indel context summary',
                exp=>"# ICS\t[2]id\t[3]repeat-consistent\t[4]repeat-inconsistent\t[5]not applicable\t[6]c/(c+i) ratio"
            },
            {
                id=>'ICL',
                header=>'ICL, Indel context by length',
                exp=>"# ICL\t[2]id\t[3]length of repeat element\t[4]repeat-consistent deletions)\t[5]repeat-inconsistent deletions\t[6]consistent insertions\t[7]inconsistent insertions\t[8]c/(c+i) ratio"
            },
            {
                id=>'QUAL',
                header=>'QUAL, Stats by quality',
                exp=>"# QUAL\t[2]id\t[3]Quality\t[4]number of SNPs\t[5]number of transitions (1st ALT)\t[6]number of transversions (1st ALT)\t[7]number of indels"
            },
            {
                id=>'HWE',
                header=>'HWE',
                exp=>"# HWE\t[2]id\t[3]1st ALT allele frequency\t[4]Number of observations\t[5]25th percentile\t[6]median\t[7]75th percentile",
            },
        ],
        SN_keys=>[
            'number of samples:',
            'number of records:',
            'number of no-ALTs:',
            'number of SNPs:',
            'number of MNPs:',
            'number of indels:',
            'number of others:',
            'number of multiallelic sites:',
            'number of multiallelic SNP sites:',
        ],
    };
    for my $sec (@{$$opts{sections}}) { $$opts{exp}{$$sec{id}} = $$sec{exp}; $$opts{id2sec}{$$sec{id}} = $sec; }
    while (defined(my $arg=shift(@ARGV)))
    {
        if (                 $arg eq '--no-plots' ) { $$opts{make_plots}=0; next; }
        if ( $arg eq '-P' || $arg eq '--no-PDF' ) { $$opts{make_pdf}=0; next; }
        if ( $arg eq '-r' || $arg eq '--rasterize' ) { $$opts{rasterize}=1; $$opts{pdf_plots} = 0; next; }
        if ( $arg eq '-m' || $arg eq '--merge' ) { $$opts{make_plots}=0; $$opts{make_pdf}=0; $$opts{merge}=1; next; }
        if ( $arg eq '-s' || $arg eq '--sample-names' ) { $$opts{use_sample_names}=1; next; }
        if ( $arg eq '-t' || $arg eq '--title' ) { push @{$$opts{titles}},shift(@ARGV); next; }
        if ( $arg eq '-T' || $arg eq '--main-title' ) { $$opts{main_title} = shift(@ARGV); next; }
        if ( $arg eq '-p' || $arg eq '--prefix' ) { $$opts{prefix}=shift(@ARGV); next; }
        if ( $arg eq '-?' || $arg eq '-h' || $arg eq '--help' ) { usage(); exit 0; }
        if ( -e $arg ) { push @{$$opts{vcfstats}},$arg; next; }
        error("Unknown parameter or non-existent file \"$arg\". Run -h for help.\n");
    }
    if ( !exists($$opts{vcfstats}) ) { error(); }
    if ( !exists($$opts{prefix}) )
    {
        if ( !$$opts{merge} ) { error("Expected -p parameter.\n") }
        $$opts{prefix} = '.';
    }
    elsif ( $$opts{merge} ) { error("Only one of -p or -m should be given.\n"); }
    if ( $$opts{merge} && @{$$opts{vcfstats}} < 2 ) { error("Nothing to merge\n") }

    $$opts{dir} = $$opts{prefix};
    $$opts{logfile} = "plot-vcfstats.log";
    if ( !-d $$opts{dir} ) { `mkdir -p $$opts{dir}`; }
    `> $$opts{dir}/$$opts{logfile}` unless $$opts{merge};
    return $opts;
}


sub plot
{
    my ($opts) = @_;
    if ( !exists($$opts{plt_fh}) ) { return; }
    close($$opts{plt_fh}) or error("close $$opts{plt_fh}");
    my $cmd = "python $$opts{plt_file}";
    print STDERR "Plotting graphs: $cmd\n" unless !$$opts{verbose};
    system($cmd);
    if ( $? ) { error("The command exited with non-zero status $?:\n\t$cmd\n\n"); }
}


sub parse_vcfstats
{
    my ($opts) = @_;
    for (my $i=0; $i<@{$$opts{vcfstats}}; $i++) { parse_vcfstats1($opts,$i); }

    # Check sanity
    if ( !exists($$opts{dat}{ID}{0}) )
    {
        error("Sanity check failed: no stats found by vcfstats??\n");
    }

    # Set titles
    my %file2title;
    my %title2file;
    if ( exists($$opts{titles}) )
    {
        for (my $i=0; $i<@{$$opts{titles}}; $i++)
        {
            if ( !exists($$opts{dat}{ID}{$i}) ) { next; }
            $file2title{$$opts{dat}{ID}{$i}[0][0]} = $$opts{titles}[$i];
            $title2file{$$opts{titles}[$i]} = $$opts{dat}{ID}{$i}[0][0];
        }
    }
    for my $id (file_ids($opts))
    {
        if ( @{$$opts{dat}{ID}{$id}[0]}>1 ) { next; }   # shared stats of two files
        my $file = $$opts{dat}{ID}{$id}[0][0];
        if ( !exists($file2title{$file}) )  # create short title
        {
            my $bname = $file;
            $bname =~ s{^.*/}{};
            $bname =~ s{\.vcf\.gz$}{}i;
            if ( length($bname) > 5 ) { $bname = substr($bname,0,5); }
            my $i = 0;
            my $title = $bname;
            while ( exists($title2file{$title}) ) { $title = $bname.chr(66+$i); $i++; }
            $file2title{$file} = $title;
            $title2file{$title} = $file;
        }
    }
    for my $id (file_ids($opts))
    {
        my @titles;
        for my $file (@{$$opts{dat}{ID}{$id}[0]}) { push @titles, $file2title{$file} if $file2title{$file}; }
        $$opts{title}{$id} = join(' + ',@titles);
    }

    # mapping from file names to list of IDs
    for my $id (file_ids($opts))
    {
        my @files;
        for my $file (@{$$opts{dat}{ID}{$id}[0]})
        {
            push @{$$opts{file2ids}{$file}}, $id;
        }
    }

    # check sanity of the file merge: were the correct files merged?
    if ( exists($$opts{coalesced_files}) && $$opts{verbose} )
    {
        print STDERR "The vcfstats outputs have been merged as follows:\n";
        my %printed;
        for my $id (keys %{$$opts{coalesced_files}})
        {
            for (my $i=0; $i<@{$$opts{coalesced_files}{$id}}; $i++)
            {
                for (my $j=0; $j<@{$$opts{coalesced_files}{$id}[$i]}; $j++)
                {
                    if ( exists($printed{$$opts{dat}{ID}{$id}[$i][$j]}) ) { next; }
                    print STDERR "\t$$opts{dat}{ID}{$id}[$i][$j]\n";
                    for my $file (keys %{$$opts{coalesced_files}{$id}[$i][$j]})
                    {
                        my $n = $$opts{coalesced_files}{$id}[$i][$j]{$file};
                        print STDERR "\t\t$file", ($n>1 ? "\t..\t${n}x" : ''),"\n";
                    }
                    $printed{$$opts{dat}{ID}{$id}[$i][$j]} = 1;
                }
            }
        }
    }
}

sub add_to_values
{
    my ($dst,$src,$cmp) = @_;
    my $id = 0;
    my $is = 0;
    while ($is<@$src)
    {
        while ( $id<@$dst && &$cmp($$src[$is][0],$$dst[$id][0])>0 ) { $id++; }
        if ( $id<@$dst && !&$cmp($$src[$is][0],$$dst[$id][0]) )
        {
            for (my $j=1; $j<@{$$src[$is]}; $j++) { $$dst[$id][$j] += $$src[$is][$j]; }
        }
        else { splice(@$dst,$id,0,$$src[$is]); }
        $is++;
    }
}

sub add_to_sample_values
{
    my ($dst,$src) = @_;
    my %id2i;
    for (my $i=0; $i<@$dst; $i++)
    {
        $id2i{$$dst[$i][0]} = $i;
    }
    for (my $i=0; $i<@$src; $i++)
    {
        if ( !exists($id2i{$$src[$i][0]}) ) { error("Whoops, no such dst sample: $$src[$i][0]\n"); }
        my $di = $id2i{$$src[$i][0]};
        for (my $j=1; $j<@{$$src[$i]}; $j++)
        {
            $$dst[$di][$j] += $$src[$i][$j];
        }
    }
}

sub merge_PSC
{
    my ($a,$b,$n) = @_;
    for (my $i=0; $i<@$a; $i++) { $$a[$i][7] *= $n; }   # average DP
    add_to_sample_values($a,$b);
    for (my $i=0; $i<@$a; $i++) { $$a[$i][7] /= $n+1; }
}

sub merge_PSI
{
    my ($a,$b,$n) = @_;
    add_to_sample_values($a,$b);
    for (my $i=0; $i<@$b; $i++) { $$a[$i][4] = sprintf "%.2f", ($$a[$i][1]+$$a[$i][2] ? $$a[$i][2]/($$a[$i][1]+$$a[$i][2]) : 0); }
}

sub rglob
{
    my ($a,$b) = @_;
    if ( $a eq $b ) { return $a; }
    $a =~ s/\*//;
    my $la = length($a);
    my $lb = length($b);
    my $i = 0;
    while ( $i<$la && $i<$lb && substr($a,$i,1) eq substr($b,$i,1) ) { $i++; }
    $la--; $lb--;
    while ( $la>$i && $lb>$i && substr($a,$la,1) eq substr($b,$lb,1) ) { $la--; $lb--; }
    $la = $la==$i && $lb==$i ? 1 : $la-$i;
    substr($a,$i,$la,'*');
    return $a;
}

sub merge_id
{
    # merge id filenames
    my ($opts,$dst,$src,$id) = @_;
    for (my $i=0; $i<@{$$src{$id}}; $i++)
    {
        for (my $j=0; $j<@{$$src{$id}[$i]}; $j++)
        {
            my $gname = rglob($$dst{$id}[$i][$j], $$src{$id}[$i][$j]);
            $$dst{$id}[$i][$j] = $gname;
            $$opts{coalesced_files}{$id}[$i][$j]{$$src{$id}[$i][$j]}++;
        }
    }
}

sub add_to_avg
{
    my ($dst,$src,$n) = @_;
    for (my $i=0; $i<@$src; $i++)
    {
        if ( ref($$dst[$i]) eq 'ARRAY' )
        {
            for (my $j=0; $j<@{$$dst[$i]}; $j++)
            {
                $$dst[$i][$j] = ($n*$$dst[$i][$j]+$$src[$i][$j])/($n+1);
            }
        }
        else
        {
            $$dst[$i] = ($n*$$dst[$i]+$$src[$i])/($n+1);
        }
    }
}

sub cmp_str($$) { my ($a,$b) = @_; return $a cmp $b; }
sub cmp_num($$) { my ($a,$b) = @_; return $a <=> $b; }
sub cmp_num_op($$)
{
    # numeric compare with operators
    # Cases like <3, >500 make it complicated
    my ($a,$b) = @_;
    my $xa = '=';
    my $xb = '=';
    if ( $a=~/^(\D+)/ ) { $xa = $1; $a = $'; }
    if ( $b=~/^(\D+)/ ) { $xb = $1; $b = $'; }
    if ( $a==$b ) { return $xa cmp $xb; }
    $a <=> $b;
}

sub merge_dp
{
    my ($a,$b) = @_;
    add_to_values($a,$b,\&cmp_num_op);
    # recalculate fraction of GTs and fraction of sites, cannot be simply summed
    my $gsum = 0; # genotype sum
    my $ssum = 0; # site sum
    for (my $i=0; $i<@$a; $i++)
    {
        $gsum += $$a[$i][1];
        if (@{$$a[$i]}>3) {
            $ssum += $$a[$i][3];
        }
        else{
            push @{$$a[$i]}, (0,0); # older stats files will not have last 2 columns for (number of sites, fraction of sites), so fill in as zero
        }
    }
    for (my $i=0; $i<@$a; $i++)
    {
        $$a[$i][2] = $gsum ? $$a[$i][1]*100./$gsum : 0;
        $$a[$i][4] = $ssum ? $$a[$i][3]*100./$ssum : 0;
    }
}

sub merge_GCsS
{
    my ($a,$b,$n) = @_;
    # average the non-ref discordance rate
    for (my $i=0; $i<@$a; $i++) { $$a[$i][1] *= $n; }
    add_to_sample_values($a,$b);
    for (my $i=0; $i<@$a; $i++) { $$a[$i][1] /= $n+1; }
}

sub merge_FS
{
    my ($a,$b) = @_;
    for (my $i=0; $i<@$a; $i++)
    {
        for (my $j=0; $j<3; $j++) { $$a[$i][$j] += $$b[$i][$j]; }
        $$a[$i][3] = sprintf "%.2f", ($$a[$i][0] + $$a[$i][1]) ? $$a[$i][1]/($$a[$i][0] + $$a[$i][1]) : 0;

        for (my $j=4; $j<7; $j++) { $$a[$i][$j] += $$b[$i][$j]; }
        $$a[$i][7] = sprintf "%.2f", ($$a[$i][4] + $$a[$i][5]) ? $$a[$i][5]/($$a[$i][4] + $$a[$i][5]) : 0;
    }
}

sub merge_ICS
{
    my ($a,$b) = @_;
    for (my $i=0; $i<@$a; $i++)
    {
        for (my $j=0; $j<3; $j++) { $$a[$i][$j] += $$b[$i][$j]; }
        $$a[$i][3] = sprintf "%.4f", ($$a[$i][0] + $$a[$i][1]) ? $$a[$i][0]/($$a[$i][0] + $$a[$i][1]) : 0;
    }
}

sub merge_ICL
{
    my ($a,$b) = @_;
    for (my $i=0; $i<@$a; $i++)
    {
        for (my $j=1; $j<5; $j++) { $$a[$i][$j] += $$b[$i][$j]; }
        $$a[$i][5] = sprintf "%.4f", ($$a[$i][2] + $$a[$i][4]) ? ($$a[$i][1] + $$a[$i][3])/($$a[$i][1] + $$a[$i][2] + $$a[$i][3] + $$a[$i][4]) : 0;
    }
}

sub merge_TSTV
{
    my ($a,$b) = @_;
    for (my $i=0; $i<@$a; $i++)
    {
        for (my $j=0; $j<2; $j++) { $$a[$i][$j] += $$b[$i][$j]; }
        $$a[$i][2] = sprintf "%.2f", $$a[$i][1] ? $$a[$i][0]/$$a[$i][1] : 0;

        for (my $j=3; $j<5; $j++) { $$a[$i][$j] += $$b[$i][$j]; }
        $$a[$i][5] = sprintf "%.2f", $$a[$i][4] ? $$a[$i][3]/$$a[$i][4] : 0;
    }
}

sub merge_GCsAF
{
    my ($a,$b) = @_;
    # recalculate r2
    for (my $i=0; $i<@$a; $i++) { $$a[$i][7] *= $$a[$i][8]; }
    for (my $i=0; $i<@$b; $i++) { $$b[$i][7] *= $$b[$i][8]; }
    add_to_values($a,$b,\&cmp_num_op);
    for (my $i=0; $i<@$a; $i++) { $$a[$i][7] /= $$a[$i][8]; }
}

sub parse_vcfstats1
{
    my ($opts,$i) = @_;
    my $file = $$opts{vcfstats}[$i];
    print STDERR "Parsing bcftools stats output: $file\n" unless !$$opts{verbose};
    open(my $fh,'<',$file) or error("$file: $!");
    my $line = <$fh>;
    if ( !$line or !($line=~/^# This file was produced by \S*/) ) { error("Sanity check failed: was this file generated by bcftools stats?"); }
    my %dat;
    while ($line=<$fh>)
    {
        $line =~ s/\s*$//;
        if ( $line=~/^#\s+(\S+)\t/ )
        {
            $$opts{def_line}{$1} = $line;
            next;
        }
        if ( $line=~/^#/ ) { next; }
        my @items = split(/\t/,$line);
        if ( $items[0] eq 'SN' )
        {
            $dat{$items[1]}{$items[2]} = splice(@items,3);
            next;
        }
        push @{$dat{$items[0]}{$items[1]}}, [splice(@items,2)];
    }
    close($fh);
    for my $a (keys %dat)
    {
        if ( !exists($$opts{dat}{$a}) ) { $$opts{dat}{$a} = $dat{$a}; next; } # first vcfstats file
        for my $b (keys %{$dat{$a}})
        {
            # Merging multiple vcfstats files. Honestly, this is quite hacky.
            if ( !exists($$opts{dat}{$a}{$b}) ) { $$opts{dat}{$a}{$b} = $dat{$a}{$b}; next; } # copy all, first occurance

            if ( $a eq 'ID' ) { merge_id($opts,$$opts{dat}{$a},$dat{$a},$b); }
            elsif ( ref($dat{$a}{$b}) ne 'ARRAY' ) { $$opts{dat}{$a}{$b} += $dat{$a}{$b} unless $b eq 'number of samples:'; } # SN, Summary numbers, do not sum sample counts
            elsif ( $a eq 'NRDs' ) { add_to_avg($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'NRDi' ) { add_to_avg($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'DP' ) { merge_dp($$opts{dat}{$a}{$b},$dat{$a}{$b}); }
            elsif ( $a eq 'GCsS' ) { merge_GCsS($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'GCiS' ) { merge_GCsS($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'GCsAF' ) { merge_GCsAF($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'GCiAF' ) { merge_GCsAF($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'ST' ) { add_to_values($$opts{dat}{$a}{$b},$dat{$a}{$b},\&cmp_str); }
            elsif ( $a eq 'PSC') { merge_PSC($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'PSI') { merge_PSI($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'IDD') { add_to_values($$opts{dat}{$a}{$b},$dat{$a}{$b},\&cmp_num); }
            elsif ( $a eq 'FS') { merge_FS($$opts{dat}{$a}{$b},$dat{$a}{$b}); }
            elsif ( $a eq 'ICS') { merge_ICS($$opts{dat}{$a}{$b},$dat{$a}{$b}); }
            elsif ( $a eq 'ICL') { merge_ICL($$opts{dat}{$a}{$b},$dat{$a}{$b}); }
            elsif ( $a eq 'TSTV') { merge_TSTV($$opts{dat}{$a}{$b},$dat{$a}{$b},$i); }
            elsif ( $a eq 'DBG' ) { next; }
            else { add_to_values($$opts{dat}{$a}{$b},$dat{$a}{$b},\&cmp_num_op); } # SiS AF IDD
        }
    }
}

sub file_ids
{
    my ($opts) = @_;
    my $id = 0;
    my @out;
    while ( exists($$opts{dat}{ID}) && exists($$opts{dat}{ID}{$id}) ) { push @out, $id++; }
    return @out;
}

sub tprint
{
    my ($fh,@txt) = @_;
    for my $txt (@txt)
    {
        $txt =~ s/\n[ \t]+/\n/g;        # eat leading tabs
        while ( ($txt =~ /\n\t*\\t/) )
        {
            $txt =~ s/(\n\t*)\\t/$1\t/g;    # replace escaped tabs (\\t) with tabs
        }
        print $fh $txt;
    }
}

sub init_plots
{
    my ($opts) = @_;

    $$opts{plt_file} = "plot.py";

    my $titles = "# Title abbreviations:\n";
    for my $id (file_ids($opts))
    {
        $titles .= "# \t $id .. $$opts{title}{$id} .. $$opts{dat}{ID}{$id}[0][0]\n";
    }
    $titles .= "#";

    open(my $fh,'>',$$opts{plt_file}) or error("$$opts{plt_file}: $!");
    tprint $fh, qq[
        # This file was produced by plot-vcfstats, the command line was:
        #   $$opts{args}
        #
        # Edit as necessary and recreate the plots by running
        #   python $$opts{plt_file}
        #
        $titles

        # Set to 1 to plot in PDF instead of PNG
        pdf_plots = $$opts{pdf_plots}

        # Use logarithimic X axis for allele frequency plots
        af_xlog = 0

        # Plots to generate, set to 0 to disable
        plot_venn_snps = 1
        plot_venn_indels = 1
        plot_tstv_by_sample = 1
        plot_hethom_by_sample = 1
        plot_snps_by_sample = 1
        plot_indels_by_sample = 1
        plot_singletons_by_sample = 1
        plot_depth_by_sample = 1
        plot_SNP_count_by_af = 1
        plot_Indel_count_by_af = 1
        plot_SNP_overlap_by_af = 1
        plot_Indel_overlap_by_af = 1
        plot_dp_dist = 1
        plot_hwe = 1
        plot_concordance_by_af = 1
        plot_r2_by_af = 1
        plot_discordance_by_sample = 1
        plot_tstv_by_af = 1
        plot_indel_dist = 1
        plot_tstv_by_qual = 1
        plot_substitutions = 1


        # Set to 1 to use sample names for xticks instead of numeric sequential IDs
        #   and adjust margins and font properties if necessary
        sample_names   = $$opts{use_sample_names}
        sample_margins = {'right':0.98, 'left':0.07, 'bottom':0.2}
        sample_font    = {'rotation':45, 'ha':'right', 'fontsize':8}

        if sample_names==0: sample_margins=(); sample_font=();


        #-------------------------------------------------


        import matplotlib as mpl
        mpl.use('Agg')
        import matplotlib.pyplot as plt

        import csv
        csv.register_dialect('tab', delimiter='\\t', quoting=csv.QUOTE_NONE)

        import numpy
        def smooth(x,window_len=11,window='hanning'):
        \\tif x.ndim != 1: raise ValueError("The function 'smooth' only accepts 1 dimension arrays.")
        \\tif x.size < window_len: return x
        \\tif window_len<3: return x
        \\tif not window in ['flat', 'hanning', 'hamming', 'bartlett', 'blackman']: raise ValueError("Window is on of 'flat', 'hanning', 'hamming', 'bartlett', 'blackman'")
        \\ts = numpy.r_[x[window_len-1:0:-1],x,x[-1:-window_len:-1]]
        \\tif window == 'flat': # moving average
        \\t\\tw = numpy.ones(window_len,'d')
        \\telse:
        \\t\\tw = eval('numpy.'+window+'(window_len)')
        \\ty = numpy.convolve(w/w.sum(),s,mode='valid')
        \\treturn y[(window_len/2-1):-(window_len/2)]

        ];
    $$opts{plt_fh} = $fh;
}

sub percentile
{
    my ($p,@vals) = @_;
    my $N = 0;
    for my $val (@vals) { $N += $val; }
    my $n = $p*($N+1)/100.;
    my $k = int($n);
    my $d = $n-$k;
    if ( $k<=0 ) { return 0; }
    if ( $k>=$N ) { return scalar @vals-1; }
    my $cnt;
    for (my $i=0; $i<@vals; $i++)
    {
        $cnt += $vals[$i];
        if ( $cnt>=$k ) { return $i; }
    }
    error("FIXME: this should not happen [percentile]\n");
}

sub get_values
{
    my ($opts,$id,$key,$i,$j) = @_;
    if ( !exists($$opts{dat}{$key}) ) { return (); }
    if ( !exists($$opts{dat}{$key}{$id}) ) { return (); }
    my $fields_ok = 1;
    if ( !exists($$opts{exp}{$key}) ) { error("todo: sanity check for $key\n"); }
    if ( exists($$opts{def_line}{$key}) && $$opts{def_line}{$key} ne $$opts{exp}{$key} && !$$opts{def_line_warned}{$key} )
    {
        warn("Warning: Possible version mismatch, the definition line differs\n\texpected: $$opts{exp}{$key}\n\tfound:    $$opts{def_line}{$key}\n");
        $$opts{def_line_warned}{$key} = 1;
    }
    if ( defined $i )
    {
        if ( defined $j ) { return $$opts{dat}{$key}{$id}[$i][$j]; }
        return (@{$$opts{dat}{$key}{$id}[$i]});
    }
    return (@{$$opts{dat}{$key}{$id}});
}

sub get_value
{
    my ($opts,$id,$key) = @_;
    if ( !exists($$opts{dat}{$id}) ) { return undef; }
    if ( !exists($$opts{dat}{$id}{$key}) ) { return undef}
    return $$opts{dat}{$id}{$key};
}

sub plot_venn_bars
{
    my ($opts) = @_;

    my @ids  = file_ids($opts);
    if ( @ids != 3 ) { return; }

    my (@snps,@indels,@tstv,@snp_titles,@indel_titles);
    for my $id (0..2)
    {
        push @snps, get_value($opts,$id,'number of SNPs:');
        push @indels, get_value($opts,$id,'number of indels:');
        push @tstv, sprintf("%.2f",get_values($opts,$id,'TSTV',0,5));
        push @snp_titles, "$$opts{title}{$id}\\nts/tv $tstv[$id]\\n" .bignum($snps[$id]);
        my @fs = get_values($opts,$id,'FS');
        my $fs = @fs ? "frm $fs[0][3]\\n" : '';
        push @indel_titles, "$$opts{title}{$id}\\n$fs" .bignum($indels[$id]);
    }

    my $fh = $$opts{plt_fh};
    tprint $fh, qq[

            if plot_venn_snps:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.bar([1,2,3],[$snps[0],$snps[2],$snps[1]],align='center',color='$$opts{id2col}[0]',width=0.3)
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tax1.set_xlim(0.5,3.5)
            \\tplt.xticks([1,2,3],('$snp_titles[0]','$snp_titles[2]','$snp_titles[1]'))
            \\tplt.title('Number of SNPs')
            \\tplt.subplots_adjust(right=0.95,bottom=0.15)
            \\tplt.savefig('venn_bars.snps.png')
            \\tif pdf_plots: plt.savefig('venn_bars.snps.pdf')
            \\tplt.close()


            if plot_venn_indels:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.bar([1,2,3],[$indels[0],$indels[2],$indels[1]],align='center',color='$$opts{id2col}[1]',width=0.3)
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tax1.set_xlim(0.5,3.5)
            \\tplt.xticks([1,2,3],('$indel_titles[0]','$indel_titles[2]','$indel_titles[1]'))
            \\tplt.title('Number of indels')
            \\tplt.subplots_adjust(right=0.95,bottom=0.15)
            \\tplt.savefig('venn_bars.indels.png')
            \\tif pdf_plots: plt.savefig('venn_bars.indels.pdf')
            \\tplt.close()

        ];
}

sub plot_per_sample_stats
{
    my ($opts,$id) = @_;
    my @vals = get_values($opts,$id,'PSC');
    if ( !@vals ) { return; }

    my $fh   = $$opts{plt_fh};
    my $img  = "tstv_by_sample.$id";
    my $img2 = "hets_by_sample.$id";
    my $img3 = "snps_by_sample.$id";
    my $img4 = "indels_by_sample.$id";
    my $img5 = "singletons_by_sample.$id";
    my $img6 = "dp_by_sample.$id";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Sample ID\t[2]ts/tv\t[3]het/hom\t[4]nSNPs\t[5]nIndels\t[6]Average depth\t[7]nSingletons\t[8]Sample name\n";
    for (my $i=0; $i<@vals; $i++)
    {
        my $tstv = $vals[$i][5] ? $vals[$i][4]/$vals[$i][5] : 0;
        my $hethom = $vals[$i][2] ? $vals[$i][3]/$vals[$i][2] : 0;
        printf $tfh "%d\t%f\t%f\t%d\t%d\t%f\t%d\t%s\n", $i, $tstv, $hethom, $vals[$i][4]+$vals[$i][5], $vals[$i][6], $vals[$i][7], $vals[$i][8], $vals[$i][0];
    }
    close($tfh);

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append(row)

            if plot_tstv_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[1] for row in dat], 'o', color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('Ts/Tv')
            \\tax1.set_ylim(min(float(row[1]) for row in dat)-0.1,max(float(row[1]) for row in dat)+0.1)
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[7] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()


            if plot_hethom_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[2] for row in dat], 'o', color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('nHet(RA) / nHom(AA)')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[7] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img2.png')
            \\tif pdf_plots: plt.savefig('$img2.pdf')
            \\tplt.close()


            if plot_snps_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[3] for row in dat], 'o', color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('Number of SNPs')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[7] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img3.png')
            \\tif pdf_plots: plt.savefig('$img3.pdf')
            \\tplt.close()


            if plot_indels_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[4] for row in dat], 'o', color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('Number of indels')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[7] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img4.png')
            \\tif pdf_plots: plt.savefig('$img4.pdf')
            \\tplt.close()


            if plot_singletons_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[6] for row in dat], 'o', color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('Number of singletons')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[7] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img5.png')
            \\tif pdf_plots: plt.savefig('$img5.pdf')
            \\tplt.close()


            if plot_depth_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[5] for row in dat], 'o', color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('Average depth')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[7] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img6.png')
            \\tif pdf_plots: plt.savefig('$img6.pdf')
            \\tplt.close()

        ";
}

sub plot_DP
{
    my ($opts,$id) = @_;
    my @vals = get_values($opts,$id,'DP');
    if ( !@vals ) { return; }

    my $fh   = $$opts{plt_fh};
    my $img  = "depth.$id";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Depth\t[2]Cumulative number of genotypes\t[3]Number of genotypes\n";
    my $sum = 0;
    for (my $i=0; $i<@vals; $i++)
    {
        if ( $sum>99. ) { last; }
        if ( !($vals[$i][0]=~/^\d+$/) ) { next; }  # DP ">500" case
        $sum += $vals[$i][2];
        printf $tfh "%d\t%f\t%f\n", $vals[$i][0], $sum, $vals[$i][2];
    }
    close($tfh);

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append(row)

            if plot_dp_dist:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[2] for row in dat], '-^', color='k')
            \\tax1.set_ylabel('Number of genotypes [%]',color='k')
            \\tax1.set_xlabel('Depth')
            \\tax2 = ax1.twinx()
            \\tax2.plot([row[0] for row in dat], [row[1] for row in dat], '-o', color='$$opts{id2col}[$id]')
            \\tax2.set_ylabel('Cumulative number of genotypes [%]',color='$$opts{id2col}[$id]')
            \\tfor tl in ax2.get_yticklabels(): tl.set_color('$$opts{id2col}[$id]')
            \\tplt.subplots_adjust(left=0.15,bottom=0.15,right=0.87)
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()

        ";
}

sub plot_hwe
{
    my ($opts,$id) = @_;
    my @vals = get_values($opts,$id,'HWE');
    if ( !@vals ) { return; }

    my $fh   = $$opts{plt_fh};
    my $img  = "hwe.$id";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Allele Frequency\t[2]Depth\t[3]Number of hets (median)\t[4]Number of hets (25-75th percentile)\n";
    for (my $i=0; $i<@vals; $i++)
    {
        if ( !$vals[$i][1] ) { next; }
        print $tfh join("\t", @{$vals[$i]}), "\n";
    }
    close($tfh);

    tprint $fh, "


            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append(row)

            if plot_hwe and len(dat)>1:
            \\tx  = [float(row[0]) for row in dat]
            \\ty1 = smooth(numpy.array([float(row[2]) for row in dat]),40,'hanning')
            \\ty2 = smooth(numpy.array([float(row[3]) for row in dat]),40,'hanning')
            \\ty3 = smooth(numpy.array([float(row[4]) for row in dat]),40,'hanning')
            \\tdp = smooth(numpy.array([float(row[1]) for row in dat]),40,'hanning')
            \\thwe = []
            \\tfor af in x: hwe.append(2*af*(1-af))

            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tplots  = ax1.plot(x,hwe,'--',color='#ff9900',label='HWE')
            \\tplots += ax1.plot(x,y2,color='#ff9900',label='Median')
            \\tplots += ax1.plot(x,y3,color='#ffe0b2',label='25-75th percentile')
            \\tax1.fill_between(x,y1,y3, facecolor='#ffeacc',edgecolor='#ffe0b2')
            \\tax1.set_ylabel('Fraction of hets',color='#ff9900')
            \\tax1.set_xlabel('Allele frequency')
            \\tfor tl in ax1.get_yticklabels(): tl.set_color('#ff9900')
            \\tax2 = ax1.twinx()
            \\tplots += ax2.plot(x,dp, 'k', label='Number of sites')
            \\tax2.set_ylabel('Number of sites')
            \\tax2.set_yscale('log')
            \\tif af_xlog: ax1.set_xscale('log')
            \\tif af_xlog: ax2.set_xscale('log')
            \\tlabels = [l.get_label() for l in plots]
            \\tplt.legend(plots,labels,numpoints=1,markerscale=2,loc='center',prop={'size':9},frameon=False)
            \\tplt.subplots_adjust(left=0.15,bottom=0.15,right=0.86)
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()

        ";
}

sub plot_tstv_by_AF
{
    my ($opts,$id) = @_;
    my @vals = get_values($opts,$id,'AF');
    if ( !@vals ) { return; }

    my $fh   = $$opts{plt_fh};
    my $img  = "tstv_by_af.$id";
    my $vals = rebin_values(\@vals,8,0);


    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Allele frequency\t[2]Number of sites\t[3]ts/tv\n";
    for (my $i=0; $i<@$vals; $i++)
    {
        if ( $$vals[$i][2] + $$vals[$i][3] == 0 ) { next; }
        printf $tfh "%f\t%d\t%f\n",
            $$vals[$i][0],
            $$vals[$i][2] + $$vals[$i][3],
            $$vals[$i][3] ? $$vals[$i][2]/$$vals[$i][3]: 0;
    }
    close($tfh);

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append([float(x) for x in row])


            if plot_tstv_by_af and len(dat)>2:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[1] for row in dat], '-o',color='k',mec='k',markersize=3)
            \\tax1.set_ylabel('Number of sites',color='k')
            \\tax1.set_yscale('log')
            \\t#ax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tfor tl in ax1.get_yticklabels(): tl.set_color('k')
            \\tax1.set_xlabel('Non-ref allele frequency')
            \\tax2 = ax1.twinx()
            \\tax2.plot([row[0] for row in dat], [row[2] for row in dat], '-o',color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]',markersize=3)
            \\tax2.set_ylabel('Ts/Tv',color='$$opts{id2col}[$id]')
            \\tax2.set_ylim(0,0.5+max(3,max(row[2] for row in dat)))
            \\tax1.set_xlim(0,1)
            \\tfor tl in ax2.get_yticklabels(): tl.set_color('$$opts{id2col}[$id]')
            \\tplt.subplots_adjust(right=0.88,left=0.15,bottom=0.11)
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()

        ";
}

sub plot_tstv_by_QUAL
{
    my ($opts,$id) = @_;
    my @vals = get_values($opts,$id,'QUAL');
    if ( !@vals ) { return; }

    my $fh   = $$opts{plt_fh};
    my $img  = "tstv_by_qual.$id";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Quality\t[2]Number of sites\t[3]Marginal Ts/Tv\n";

    my @dat = ();
    my $ntot = 0;
    for my $val (@vals)
    {
        push @dat, [ $$val[0], $$val[2], $$val[3] ];    # qual, nts, ntv
        $ntot += $$val[2] + $$val[3];
    }
    my @sdat = sort { $$b[0] <=> $$a[0] } @dat;
    push @sdat, [-1];
    my $dn    = $ntot*0.05;
    my $qprev = $sdat[0][0];
    my $nts   = 0;
    my $ntv   = 0;
    my $nout  = 0;
    for my $rec (@sdat)
    {
        if ( $$rec[0]==-1 or $nts+$ntv > $dn )
        {
            if ( $ntv ) {  printf $tfh "$qprev\t%d\t%f\n", $nts+$ntv+$nout,$nts/$ntv; }
            if ( $$rec[0]==-1 ) { last; }
            $nout += $nts+$ntv;
            $nts   = 0;
            $ntv   = 0;
            $qprev = $$rec[0];
        }
        $nts += $$rec[1];
        $ntv += $$rec[2];
    }
    close($tfh) or error("close $img.dat");

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append([float(x) for x in row])

            if plot_tstv_by_qual and len(dat)>2:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[1] for row in dat], [row[2] for row in dat], '^-', ms=3, mec='$$opts{id2col}[$id]', color='$$opts{id2col}[$id]')
            \\tax1.set_ylabel('Ts/Tv',fontsize=10)
            \\tax1.set_xlabel('Number of sites\\n(sorted by QUAL, descending)',fontsize=10)
            \\tax1.ticklabel_format(style='sci', scilimits=(-3,2), axis='x')
            \\tax1.set_ylim(min(2,min(row[2] for row in dat))-0.3,0.3+max(2.2,max(row[2] for row in dat)))

            \\tplt.subplots_adjust(right=0.88,left=0.15,bottom=0.15)
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()

        ";
}

sub rebin_values
{
    my ($vals,$bin_size,$col,%args) = @_;
    my %avg  = exists($args{avg}) ? map {$_=>1} @{$args{avg}} : ();
    my $prev = $$vals[0][$col];
    my $iout = 0;
    my $nsum = 0;
    my (@dat,@out);
    for (my $i=0; $i<@$vals; $i++)
    {
        for (my $icol=0; $icol<@{$$vals[$i]}; $icol++)
        {
            if ( $icol==$col ) { next; }
            $dat[$icol] += $$vals[$i][$icol];
        }
        $nsum++;
        if ( $i+1<@$vals && $$vals[$i][$col] - $prev < $bin_size ) { next; }
        $dat[$col] = $prev;
        for (my $icol=0; $icol<@{$$vals[$i]}; $icol++)
        {
            $out[$iout][$icol] = $dat[$icol] ? $dat[$icol] : 0;
            if ( $avg{$icol} && $nsum ) { $out[$iout][$icol] /= $nsum; }
        }
        $nsum = 0;
        @dat = ();
        $iout++;
        $prev = $$vals[$i][$col];
    }
    return \@out;
}

sub plot_concordance_by_AF
{
    my ($opts) = @_;
    my @vals = get_values($opts,2,'GCsAF');
    if ( !@vals ) { return; }

    # create a local copy and prepare r2 for rebinning
    @vals = @{ dclone(\@vals) };
    for (my $i=0; $i<@vals; $i++) { $vals[$i][7] *= $vals[$i][8]; }
    my $vals = rebin_values(\@vals,0.01,0);
    my $fh   = $$opts{plt_fh};
    my $img  = "gts_by_af";
    my $img2 = "r2_by_af";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Allele Frequency\t[2]RR concordance\t[3]RA concordance\t[4]AA concordance\t[5]nRR\t[6]nRA\t[7]nAA\t[8]R^2\t[9]Number of genotypes\n";
    for (my $i=0; $i<@$vals; $i++)
    {
        printf $tfh "%f\t%f\t%f\t%f\t%d\t%d\t%d\t%f\t%d\n",
            $$vals[$i][0],
            $$vals[$i][1]+$$vals[$i][4] ? $$vals[$i][1]/($$vals[$i][1]+$$vals[$i][4]) : 1,
            $$vals[$i][2]+$$vals[$i][5] ? $$vals[$i][2]/($$vals[$i][2]+$$vals[$i][5]) : 1,
            $$vals[$i][3]+$$vals[$i][6] ? $$vals[$i][3]/($$vals[$i][3]+$$vals[$i][6]) : 1,
            $$vals[$i][1]+$$vals[$i][4],
            $$vals[$i][2]+$$vals[$i][5],
            $$vals[$i][3]+$$vals[$i][6],
            $$vals[$i][8] ? $$vals[$i][7]/$$vals[$i][8] : 1,
            $$vals[$i][8];
    }
    close($tfh);

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append(row)

            if plot_concordance_by_af and len(dat)>1:
            \\tfig = plt.figure(figsize=($$opts{img_width}*1.2,$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[1] for row in dat],'.',color='$$opts{id2col}[1]',label='Hom RR')
            \\tax1.plot([row[0] for row in dat], [row[2] for row in dat],'.',color='$$opts{id2col}[0]',label='Het RA')
            \\tax1.plot([row[0] for row in dat], [row[3] for row in dat],'.',color='k',label='Hom AA')
            \\tax1.set_xlabel('Non-ref allele frequency')
            \\tax1.set_ylabel('Concordance')
            \\tleg = ax1.legend(title='Concordance:',numpoints=1,markerscale=2,loc='best',prop={'size':9})
            \\tleg.draw_frame(False)
            \\tplt.setp(leg.get_title(),fontsize=9)
            \\tax2 = ax1.twinx()
            \\tax2.plot([row[0] for row in dat], [row[4] for row in dat],color='$$opts{id2col}[1]')
            \\tax2.plot([row[0] for row in dat], [row[5] for row in dat],color='$$opts{id2col}[0]')
            \\tax2.plot([row[0] for row in dat], [row[6] for row in dat],color='k')
            \\tax2.set_ylabel('Number of genotypes')
            \\tax2.set_yscale('log')
            \\tif af_xlog: ax1.set_xscale('log')
            \\tif af_xlog: ax2.set_xscale('log')
            \\tplt.subplots_adjust(left=0.15,right=0.83,bottom=0.11)
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()

            if plot_r2_by_af and len(dat)>1:
            \\tfig = plt.figure(figsize=($$opts{img_width}*1.3,$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax2 = ax1.twinx()
            \\tax1.set_zorder(ax2.get_zorder()+1)
            \\tax1.patch.set_visible(False)
            \\tax2.plot([row[0] for row in dat], [row[8] for row in dat], '-o', color='r',mec='r',markersize=3)
            \\tax1.plot([row[0] for row in dat], [row[7] for row in dat], '-^', color='k',markersize=3)
            \\tfor tl in ax2.get_yticklabels(): tl.set_color('r')
            \\tax2.set_ylabel('Number of genotypes', color='r')
            \\tax2.set_yscale('log')
            \\tif af_xlog: ax1.set_xscale('log')
            \\tif af_xlog: ax2.set_xscale('log')
            \\tax1.set_ylabel('Aggregate allelic R\$^2\$', color='k')
            \\tax1.set_xlabel('Non-ref allele frequency')
            \\tplt.subplots_adjust(left=0.19,right=0.83,bottom=0.11)
            \\tplt.savefig('$img2.png')
            \\tif pdf_plots: plt.savefig('$img2.pdf')
            \\tplt.close()

        ";
}

sub plot_concordance_by_sample
{
    my ($opts) = @_;
    my @vals = get_values($opts,2,'GCsS');
    if ( !@vals ) { return; }

    my $fh   = $$opts{plt_fh};
    my $img  = "gts_by_sample";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Sample ID\t[2]Discordance\t[3]Sample Name\n";
    for (my $i=0; $i<@vals; $i++)
    {
        printf $tfh "%d\t%f\t%s\n", $i, $vals[$i][1], $vals[$i][0];
    }
    close($tfh);

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append(row)

            if plot_discordance_by_sample:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.plot([row[0] for row in dat], [row[1] for row in dat],'.',color='orange')
            \\tax1.set_ylabel('Non-ref discordance')
            \\tax1.set_ylim(0,)
            \\tif sample_names:
            \\t\\t     plt.xticks([int(row[0]) for row in dat],[row[2] for row in dat],**sample_font)
            \\t\\t     plt.subplots_adjust(**sample_margins)
            \\telse:
            \\t\\t     plt.subplots_adjust(right=0.98,left=0.07,bottom=0.17)
            \\t\\t     ax1.set_xlabel('Sample ID')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()


        ";
}

sub plot_counts_by_AF
{
    my ($opts) = @_;
    plot_counts_by_AF_col($opts,1,'SNP');
    plot_counts_by_AF_col($opts,4,'Indel');
}

sub plot_counts_by_AF_col
{
    my ($opts,$col,$title) = @_;

    my $fh  = $$opts{plt_fh};
    my $img = "counts_by_af.".lc($title)."s";

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]id\t[2]Nonref Allele Frequency\t[3]Number of sites\n";
    for my $id (file_ids($opts))
    {
        my @tmp = get_values($opts,$id,'AF');
        my $vals = rebin_values(\@tmp,1,0);
        for my $val (@$vals)
        {
            if ( !$$val[$col] ) { next; }
            print $tfh "$id\t$$val[0]\t$$val[$col]\n";
        }
    }
    close($tfh);

    tprint $fh, "

            dat = {}
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] == '#': continue
            \\t\\tid = int(row[0])
            \\t\\tif id not in dat: dat[id] = []
            \\t\\tdat[id].append([float(row[1]),float(row[2])])

            if plot_${title}_count_by_af:
            \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
            \\tax1 = fig.add_subplot(111)
            \\tax1.set_ylabel('Number of sites')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tax1.set_yscale('log')
            \\tif af_xlog: ax1.set_xscale('log')
            \\tax1.set_xlabel('Non-reference allele frequency')
            \\tax1.set_xlim(-0.05,1.05)
            \\thas_data = 0
        ";
    for my $id (file_ids($opts))
    {
        tprint $fh, "
            \\tif $id in dat and len(dat[$id])>2:
            \\t\\tax1.plot([row[0] for row in dat[$id]], [row[1] for row in dat[$id]], '-o',markersize=3, color='$$opts{id2col}[$id]',mec='$$opts{id2col}[$id]',label='$$opts{title}{$id}')
            \\t\\thas_data = 1
        ";
    }
    tprint $fh, "
            \\tif has_data:
            \\t\\tax1.legend(numpoints=1,markerscale=1,loc='best',prop={'size':10},frameon=False)
            \\t\\tplt.title('$title count by AF')
            \\t\\tplt.subplots_adjust(bottom=0.2,left=0.1,right=0.95)
            \\t\\tplt.savefig('$img.png')
            \\t\\tif pdf_plots: plt.savefig('$img.pdf')
            \\t\\tplt.close()


        ";
}

sub plot_overlap_by_AF
{
    my ($opts) = @_;
    plot_overlap_by_AF_col($opts,1,'SNP');
    plot_overlap_by_AF_col($opts,4,'Indel');
}

sub plot_overlap_by_AF_col
{
    my ($opts,$col,$title) = @_;

    my @ids  = file_ids($opts);
    if ( @ids != 3 ) { return; }

    my ($ia,$ib,$iab);
    for (my $i=0; $i<@ids; $i++)
    {
        if ( @{$$opts{dat}{ID}{$ids[$i]}[0]}>1 ) { $iab = $i; next; }
        if ( !defined $ia ) { $ia = $i; next; }
        $ib = $i;
    }

    my $fh  = $$opts{plt_fh};
    my $img = "overlap_by_af.".lc($title)."s";
    my @has_vals;

    my @vals_a  = get_values($opts,$ia,'AF');
    my @vals_b  = get_values($opts,$ib,'AF');
    my @vals_ab = get_values($opts,$iab,'AF');

    my (%afs,%af_a,%af_ab);
    for my $val (@vals_a) { $afs{$$val[0]} = $$val[$col]; $af_a{$$val[0]} = $$val[$col]; }
    for my $val (@vals_ab) { $afs{$$val[0]} = $$val[$col]; $af_ab{$$val[0]} = $$val[$col]; }

    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Allele frequency\t[2]Fraction of sites from $$opts{title}{$ids[$ia]} also in $$opts{title}{$ids[$ib]}\t[3]Number of sites\n";
    for my $af (sort { $a<=>$b } keys %afs)
    {
        my $a  = exists($af_a{$af})  ? $af_a{$af}  : 0;
        my $ab = exists($af_ab{$af}) ? $af_ab{$af} : 0;
        my $yval =  ($a+$ab) ? $ab * 100. / ($a + $ab) : 0;
        print $tfh "$af\t$yval\t" .($a+$ab). "\n";
    }
    close($tfh) or error("close $img.dat");

    tprint $fh, "

        dat = []

        with open('$img.dat', 'r') as f:
        \\treader = csv.reader(f, 'tab')
        \\tfor row in reader:
        \\t\\tif row[0][0] != '#': dat.append(row)

        if plot_${title}_overlap_by_af and len(dat)>1:
        \\tfig = plt.figure(figsize=(2*$$opts{img_width},$$opts{img_height}*0.7))
        \\tax1 = fig.add_subplot(111)
        \\tax1.plot([row[0] for row in dat], [row[1] for row in dat],'-o',markersize=3, color='$$opts{id2col}[1]',mec='$$opts{id2col}[1]')
        \\tax1.set_ylabel('Fraction found in $$opts{title}{$ib} [%]')
        \\tax1.set_xscale('log')
        \\tax1.set_xlabel('Non-reference allele frequency in $$opts{title}{$ia}')
        \\tax1.set_xlim(0,1.01)
        \\tplt.title('$title overlap by AF')
        \\tplt.subplots_adjust(bottom=0.2,left=0.1,right=0.95)
        \\tplt.savefig('$img.png')
        \\tif pdf_plots: plt.savefig('$img.pdf')
        \\tplt.close()
    ";
}

sub plot_indel_distribution
{
    my ($opts,$id) = @_;

    my @vals = get_values($opts,$id,'IDD');
    if ( !@vals ) { return; }

    # Set xlim to show 99 of indels but ignore outliers
    my @tmp;
    for my $id (file_ids($opts))
    {
        my @v = get_values($opts,$id,'IDD');
        for my $v (@v) { $tmp[ abs($$v[0]) ] += $$v[1]; }
    }
    my $n;
    for my $t (@tmp) { $n += $t ? $t : 0; }
    my ($sum,$xlim);
    for ($xlim=0; $xlim<@tmp; $xlim++)
    {
        $sum += $tmp[$xlim] ? $tmp[$xlim] : 0;
        if ( $sum/$n >= 0.99 ) { last; }
    }
    if ( $xlim<20 ) { $xlim=20; }

    my $fh  = $$opts{plt_fh};
    my $img = "indels.$id";


    open(my $tfh,'>',"$img.dat") or error("$img.dat: $!");
    print $tfh "# [1]Indel length\t[2]Count\n";
    for my $val (@vals) { print $tfh "$$val[0]\t$$val[1]\n"; }
    close($tfh);

    tprint $fh, "

            dat = []
            with open('$img.dat', 'r') as f:
            \\treader = csv.reader(f, 'tab')
            \\tfor row in reader:
            \\t\\tif row[0][0] != '#': dat.append([float(x) for x in row])

            if plot_indel_dist and len(dat)>0:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tax1 = fig.add_subplot(111)
            \\tax1.bar([row[0]-0.5 for row in dat], [row[1] for row in dat], color='$$opts{id2col}[0]')# , edgecolor='$$opts{id2col}[0]')
            \\tax1.set_xlabel('InDel Length')
            \\tax1.set_ylabel('Count')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tax1.set_xlim(-$xlim,$xlim)
            \\tplt.subplots_adjust(bottom=0.17)
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()
        ";
}

sub plot_substitutions
{
    my ($opts,$id) = @_;

    my @vals = get_values($opts,$id,'ST');
    if ( !@vals ) { return; }

    my $fh  = $$opts{plt_fh};
    my $img = "substitutions.$id";

    tprint $fh, "
            dat = [
        ";
    for (my $i=0; $i<@vals; $i++) { my $val=$vals[$i]; tprint $fh, "\t[$i,'$$val[0]',$$val[1]],\n"; }
    tprint $fh, "]

            if plot_substitutions:
            \\tfig = plt.figure(figsize=($$opts{img_width},$$opts{img_height}))
            \\tcm  = mpl.cm.get_cmap('autumn')
            \\tn = 12
            \\tcol = []
            \\tfor i in range(n): col.append(cm(1.*i/n))
            \\tax1 = fig.add_subplot(111)
            \\tax1.bar([row[0] for row in dat], [row[2] for row in dat], color=col)
            \\tax1.set_ylabel('Count')
            \\tax1.ticklabel_format(style='sci', scilimits=(0,0), axis='y')
            \\tax1.set_xlim(-0.5,n+0.5)
            \\tplt.xticks([row[0] for row in dat],[row[1] for row in dat],rotation=45)
            \\tplt.title('$$opts{title}{$id}')
            \\tplt.savefig('$img.png')
            \\tif pdf_plots: plt.savefig('$img.pdf')
            \\tplt.close()

        ";
}

sub singletons
{
    my ($opts,$id) = @_;
    my @si_vals   = get_values($opts,$id,'SiS');
    my $si_snps   = $si_vals[0][1];
    my $si_indels = $si_vals[0][4];
    my $si_irc    = sprintf "%.3f", $si_vals[0][6] ? $si_vals[0][5]/($si_vals[0][5]+$si_vals[0][6]) : 0;
    my $si_tstv   = sprintf "%.2f", $si_vals[0][3] ? $si_vals[0][2]/$si_vals[0][3] : 0;
    my @all_vals  = get_values($opts,$id,'AF');
    my $nsnps = 0;
    my $nindels = 0;
    for my $val (@all_vals)
    {
        $nsnps += $$val[1];
        $nindels += $$val[4];
    }
    $si_snps   = sprintf "%.1f", $nsnps ? $si_snps*100./$nsnps : 0;
    $si_indels = sprintf "%.1f", $nindels ? $si_indels*100./$nindels : 0;
    return { snps=>$si_snps, indels=>$si_indels, tstv=>$si_tstv, irc=>$si_irc };
}

sub calc_3n_n3n
{
    my (@vals) = @_;
    my $n3  = 0;
    my $nn3 = 0;
    for my $val (@vals)
    {
        if ( !($$val[0]%3) ) { $n3++; }
        else { $nn3++; }
    }
    if ( !$nn3 ) { return '-'; }
    return sprintf("%.2f", $n3/$nn3);
}

sub fmt_slide3v
{
    my ($opts, $image, $title) = @_;

    my $n = 0;
    for my $id (0..2)
    {
        if ( -e "$image.$id.$$opts{fmt}" ) { $n++; }
    }
    if ( !$n ) { return ''; }
    my $h = $$opts{tex}{slide3v}{"height$n"};
    my $slide = q[\vbox{];
    for my $id (0..2)
    {
        if ( !-e "$image.$id.$$opts{fmt}" ) { next; }
        $slide .= qq[\\centerline{\\includegraphics[$$opts{ext},height=$h]{$image.$id}}];
    }
    $slide .= '}';
    return qq[
            % $title
            %
            \\hslide{$title}{$slide}
        ];
}

sub fmt_slide3h
{
    my ($opts, $image, $title) = @_;
    my $n = 0;
    for my $id (0..2)
    {
        if ( -e "$image.$id.$$opts{fmt}" ) { $n++; }
    }
    if ( !$n ) { return ''; }
    my $w = $$opts{tex}{slide3h}{"width$n"};
    my $slide = '';
    for my $id (0..2)
    {
        if ( !-e "$image.$id.$$opts{fmt}" ) { next; }
        $slide .= qq[\\includegraphics[$$opts{ext},width=$w]{$image.$id}];
    }
    return qq[
            % $title
            %
            \\hslide{$title}{$slide}
        ];
}

sub bignum
{
    my ($num) = @_;
    if ( !defined $num ) { return ''; }
    if ( !($num=~/^\d+$/) ) { return $num; }
    my $len = length($num);
    my $out;
    for (my $i=0; $i<$len; $i++)
    {
        $out .= substr($num,$i,1);
        if ( $i+1<$len && !(($len-$i-1)%3) ) { $out .= ','; }
    }
    return $out;
}

sub create_pdf
{
    my ($opts) = @_;

    chdir($$opts{dir});

    my @ids     = file_ids($opts);
    my $width   = "25.4cm"; # todo: move all this to $$opts{tex}
    my $height  = "19cm";
    my $height1 = "13cm";
    my $width1  = "23cm";
    my $width2  = @ids==3 ? "10.5cm" : "10.5cm";
    my $width3  = @ids==3 ? "8cm" : "15cm";
    my $fmt     = $$opts{rasterize} ? 'png' : 'pdf';
    my $ext     = "type=$fmt,ext=.$fmt,read=.$fmt";
    my $args    = { ext=>$ext, width3=>$width3, n=>scalar @ids };
    $$opts{fmt} = $fmt;
    $$opts{ext} = $ext;

    # Check that xcolor is available
    my @has_xcolor = `kpsewhich xcolor.sty`;
    if ( !@has_xcolor )
    {
        warn("Note: The xcolor.sty package not available, black and white tables only...\n\n");
    }

    my $tex_file = "summary.tex";
    my $pdf_file = "summary.pdf";
    open(my $tex,'>',$tex_file) or error("$tex_file: $!");
    tprint $tex, qq[
            % This file was produced by plot-vcfstats, the command line was:
            %   $$opts{args}
            %
            % Edit as necessary and recreate the PDF by running
            %   pdflatex $tex_file
            %

            % Slides style and dimensions
            %
            \\nonstopmode
            \\documentclass[17pt]{memoir}
            \\setstocksize{$height}{$width}
            \\settrimmedsize{\\stockheight}{\\stockwidth}{*}
            \\settrims{0pt}{0pt}
            \\setlrmarginsandblock{1cm}{*}{*}
            \\setulmarginsandblock{1.5cm}{*}{*}
            \\setheadfoot{1mm}{1cm}
            \\setlength{\\parskip}{0pt}
            \\setheaderspaces{*}{1mm}{*}
            \\setmarginnotes{1mm}{1mm}{1mm}
            \\checkandfixthelayout[fixed]
            \\usepackage{charter}   % font
            \\pagestyle{plain}
            \\makeevenfoot{plain}{}{}{\\thepage}
            \\makeoddfoot{plain}{}{}{\\thepage}
            \\usepackage{graphicx}

            % For colored tables. If xcolor.sty is not available on your system,
            % download xcolor.sty.gz LaTeX class style from
            %   http://www.ukern.de/tex/xcolor.html
            % Unpack and install system-wide or place elsewhere and make available by
            % setting the TEXINPUTS environment variable (note the colon)
            %   export TEXINPUTS=some/dir:
            % The list of the recognised path can be obtained by running `kpsepath tex`
            %
            \\usepackage{multirow}
            \\setlength{\\tabcolsep}{0.6em}
            \\renewcommand{\\arraystretch}{1.2}
        ];
    if ( @has_xcolor )
    {
        tprint $tex, '\usepackage[table]{xcolor}';
    }
    else
    {
        tprint $tex, qq[
            \\newcommand{\\definecolor}[3]{}
            \\newcommand{\\columncolor}[1]{}
            \\newcommand{\\rowcolors}[4]{}
            \\newcommand{\\arrayrulecolor}[1]{}
        ];
    }
    tprint $tex, qq[
            \\definecolor{hcol1}{rgb}{1,0.6,0}
            \\definecolor{hcol2}{rgb}{1,0.68,0.2}
            \\definecolor{row1}{rgb}{1,0.88,0.7}
            \\definecolor{row2}{rgb}{1,0.92,0.8}    % #FFEBCC
            \\setlength{\\arrayrulewidth}{1.5pt}

            % Slide headings
            \\newcommand*{\\head}[1]{{\\Large\\centerline{#1}\\vskip0.5em}}

            % Slide definition
            \\newcommand*{\\hslide}[2]{%
                    \\head{#1}%
                    \\begin{vplace}[0.5]\\centerline{#2}\\end{vplace}\\newpage}
            \\newcommand{\\pdf}[2]{\\IfFileExists{#2.$fmt}{\\includegraphics[#1]{#2}}{}}


            % The actual slides
            \\begin{document}
        ];


    # Table with summary numbers
    my $slide .= q[
            \begin{minipage}{\textwidth}\centering
            \small \rowcolors*{3}{row2}{row1} \arrayrulecolor{black}
            \begin{tabular}{l | r r r | r r | r | r}
            \multicolumn{1}{>{\columncolor{hcol1}}l|}{}
            & \multicolumn{3}{>{\columncolor{hcol1}}c|}{SNPs}
            & \multicolumn{2}{>{\columncolor{hcol1}}c|}{indels}
            & \multicolumn{1}{>{\columncolor{hcol1}}c|}{MNPs}
            & \multicolumn{1}{>{\columncolor{hcol1}}c}{others}  \\\\
            %
            \multicolumn{1}{>{\columncolor{hcol2}}l|}{Callset}
            & \multicolumn{1}{>{\columncolor{hcol2}}c}{n}
            & \multicolumn{1}{>{\columncolor{hcol2}}c }{ts/tv}
            & \multicolumn{1}{>{\columncolor{hcol2}}c|}{\\footnotesize(1st ALT)}
            & \multicolumn{1}{>{\columncolor{hcol2}}c}{n}
            & \multicolumn{1}{>{\columncolor{hcol2}}c}{frm$^*$}
            & \multicolumn{1}{>{\columncolor{hcol2}}c|}{}
            & \multicolumn{1}{>{\columncolor{hcol2}}c}{} \\\\ \hline
        ];
    my %tex_titles;
    for my $id (@ids)
    {
        my $snps   = get_value($opts,$id,'number of SNPs:');
        my $indels = get_value($opts,$id,'number of indels:');
        my $mnps   = get_value($opts,$id,'number of MNPs:');
        my $others = get_value($opts,$id,'number of others:');
        my $tstv   = sprintf "%.2f",get_values($opts,$id,'TSTV',0,2);
        my $tstv1  = sprintf "%.2f",get_values($opts,$id,'TSTV',0,5);
        my @frsh   = get_values($opts,$id,'FS');
        my $frsh   = @frsh ? $frsh[0][3] : '--';
        my @rc     = get_values($opts,$id,'ICS');
        my $title  = $$opts{title}{$id};
        $title =~ s/_/\\_/g;
        $title =~ s/^\s*\*/\$*\$/;    # leading asterisks is eaten by TeX
        $tex_titles{$id} = $title;
        $slide .= qq[ $title & ] . bignum($snps) . qq[ & $tstv & $tstv1 & ] . bignum($indels) . qq[ & $frsh & ] . bignum($mnps) . ' & ' . bignum($others) . qq[ \\\\ \n];
    }
    $slide .= q[%
        \multicolumn{8}{r}{$^*$ frameshift ratio: out/(out+in)} \\\\
        \end{tabular}
        \\\\ \vspace{1em}
        \begin{tabular}{l | r r r | r r}
        \multicolumn{1}{>{\columncolor{hcol1}}l|}{}
        & \multicolumn{3}{>{\columncolor{hcol1}}c|}{singletons {\footnotesize(AC=1)}}
        & \multicolumn{2}{>{\columncolor{hcol1}}c}{multiallelic}  \\\\
        %
        \multicolumn{1}{>{\columncolor{hcol2}}l|}{Callset}
        & \multicolumn{1}{>{\columncolor{hcol2}}c}{SNPs}
        & \multicolumn{1}{>{\columncolor{hcol2}}c}{ts/tv}
        & \multicolumn{1}{>{\columncolor{hcol2}}c}{indels}
        & \multicolumn{1}{>{\columncolor{hcol2}}c}{sites}
        & \multicolumn{1}{>{\columncolor{hcol2}}c}{SNPs} \\\\ \hline
    ];
    for my $id (@ids)
    {
        my $snps  = get_value($opts,$id,'number of SNPs:');
        my $s     = singletons($opts,$id);
        my $mals  = get_value($opts,$id,'number of multiallelic sites:');
        my $msnps = get_value($opts,$id,'number of multiallelic SNP sites:');
        my $title = $tex_titles{$id};
        $slide .= qq[ $title & $$s{snps}\\% & $$s{tstv} & $$s{indels}\\% & ] . bignum($mals) . ' &' . bignum($msnps) . qq[ \\\\ \n];
    }
    $slide .= q[ \\end{tabular}
            \\vspace{2em}
            \\begin{itemize}[-]
            \\setlength{\\itemsep}{0pt}
        ];
    for my $id (@ids)
    {
        my $fname = $$opts{dat}{ID}{$id}[0][0];
        if ( $$opts{title}{$id} =~ / \+ / ) { next; }
        $fname =~ s/.{80}/$&\\\\\\hskip2em /g;
        $fname =~ s/_/\\_/g;
        $slide .= qq[\\item $tex_titles{$id} .. \\texttt{\\footnotesize $fname}\n];
    }
    $slide .= q[\\end{itemize}\\end{minipage}];
    my $title = exists($$opts{main_title}) ? $$opts{main_title} : 'Summary Numbers';
    tprint $tex, qq[
            % Table with summary numbers
            %
            \\hslide{$title}{$slide}

        ];


    # Venn bars
    if ( @ids==3 )
    {
        tprint $tex, qq[%

            % Venn numbers
            %
            \\hslide{Total counts}{%
                \\includegraphics[$ext,width=$width2]{venn_bars.snps}%
                \\includegraphics[$ext,width=$width2]{venn_bars.indels}
            }
        ];
    }

    tprint $tex, fmt_slide3v($opts, "tstv_by_sample", 'Ts/Tv by sample');
    tprint $tex, fmt_slide3v($opts, "hets_by_sample", 'Hets vs non-ref Homs by sample');
    tprint $tex, fmt_slide3v($opts, "singletons_by_sample", 'Singletons by sample {\normalsize(hets and homs)}');
    tprint $tex, fmt_slide3v($opts, "dp_by_sample", 'Average depth by sample');
    tprint $tex, fmt_slide3v($opts, "snps_by_sample", 'Number of SNPs by sample');
    tprint $tex, fmt_slide3v($opts, "indels_by_sample", 'Number of indels by sample');
    if ( scalar get_values($opts,2,'GCsS') )
    {
        tprint $tex, qq[
            % Genotype discordance by sample
            %
            \\hslide{Genotype discordance by sample}{\\pdf{$ext,width=$width1}{gts_by_sample}}

            ];
    }
    if ( scalar get_values($opts,2,'GCsAF') )
    {
        my @vals = get_values($opts,2,'NRDs');
        my $nrd = sprintf "%.2f", $vals[0][0];
        my $rr  = sprintf "%.2f", $vals[0][1];
        my $ra  = sprintf "%.2f", $vals[0][2];
        my $aa  = sprintf "%.2f", $vals[0][3];
        my $nsamples = get_value($opts,2,'number of samples:');
        my $table = qq[%
            {\\small
            \\rowcolors*{1}{row2}{row1}\\arrayrulecolor{black}
            \\begin{tabular}{c | c | c | c }
            \\multicolumn{1}{>{\\columncolor{hcol1}}c|}{REF/REF} &
            \\multicolumn{1}{>{\\columncolor{hcol1}}c|}{REF/ALT} &
            \\multicolumn{1}{>{\\columncolor{hcol1}}c|}{ALT/ALT} &
            \\multicolumn{1}{>{\\columncolor{hcol1}}c}{NRDs} \\\\ \\hline
            $rr\\% & $ra\\% & $aa\\% & $nrd\\% \\\\
            \\end{tabular}}];
        tprint $tex, qq[
                % Genotype discordance by AF
                %
                \\head{Genotype discordance by AF}\\begin{vplace}[0.7]\\centerline{$table}%
                \\centerline{\\pdf{$ext,height=$height1}{gts_by_af}}\\end{vplace}
                \\newpage

                % dosage r2 by AF
                %
                \\hslide{Allelic R\$^2\$ by AF}{\\pdf{$ext,height=$height1}{r2_by_af}}
            ];
    }
    if ( -e "counts_by_af.snps.$fmt" && -e "counts_by_af.indels.$fmt" )
    {
        tprint $tex, qq[
            % SNP and indel counts by AF
            %
            \\hslide{}{\\vbox{\\noindent\\includegraphics[$ext,width=$width1]{counts_by_af.snps}\\\\%
                \\noindent\\includegraphics[$ext,width=$width1]{counts_by_af.indels}}}
            ];
    }
    if ( -e "overlap_by_af.snps.$fmt" && -e "overlap_by_af.indels.$fmt" )
    {
        tprint $tex, qq[
            % SNP and indel overlap by AF
            %
            \\hslide{}{\\vbox{\\noindent\\includegraphics[$ext,width=$width1]{overlap_by_af.snps}\\\\%
                \\noindent\\includegraphics[$ext,width=$width1]{overlap_by_af.indels}}}
            ];
    }
    tprint $tex, fmt_slide3h($opts, "tstv_by_af", 'Ts/Tv by AF');
    tprint $tex, fmt_slide3h($opts, "tstv_by_qual", 'Ts/Tv stratified by QUAL');
    tprint $tex, fmt_slide3h($opts, "indels", 'Indel distribution');
    tprint $tex, fmt_slide3h($opts, "depth", 'Depth distribution');
    tprint $tex, fmt_slide3h($opts, "hwe", 'Number of HETs by AF');
    tprint $tex, fmt_slide3h($opts, "substitutions", 'Substitution types');
    #tprint $tex, fmt_slide3h($opts, "irc_by_af", 'Indel Repeat Consistency by AF');
    #tprint $tex, fmt_slide3h($opts, "irc_by_rlen", 'Indel Consistency by Repeat Type');

    tprint $tex, "\n\n\\end{document}\n";
    close($tex);

    $tex_file =~ s{^.+/}{};
    my $cmd = "pdflatex $tex_file >$$opts{logfile} 2>&1";
    print STDERR "Creating PDF: $cmd\n" unless !$$opts{verbose};
    system($cmd);
    if ( $? ) { error("The command exited with non-zero status, please consult the output of pdflatex: $$opts{dir}$$opts{logfile}\n\n"); }
    print STDERR "Finished: $$opts{dir}/$pdf_file\n" unless !$$opts{verbose};
}

sub merge_vcfstats
{
    my ($opts) = @_;

    my $fh = *STDOUT;
    if ( !$$opts{merge} )
    {
        open($fh,'>',"merge.chk") or error("merge.chk: $!\n");
    }

    print $fh "# This file was produced by plot-vcfstats, the command line was:\n#   $$opts{args}\n#\n";

    for my $sec (@{$$opts{sections}})
    {
        my $sid = $$sec{id};
        if ( !exists($$opts{dat}{$sid}) ) { next; }

        print $fh "# $$sec{header}\n$$sec{exp}\n";
        for my $id (sort keys %{$$opts{dat}{$sid}})
        {
            for my $rec (@{$$opts{dat}{$sid}{$id}})
            {
                print $fh "$sid\t$id\t", join("\t",@$rec), "\n";
            }
        }

        if ( $sid eq 'ID' )
        {
            print $fh "# $$opts{id2sec}{SN}{header}\n$$opts{id2sec}{SN}{exp}\n";
            # output summary numbers here
            for my $id (keys %{$$opts{dat}})
            {
                if ( exists($$opts{exp}{$id}) ) { next; }
                for my $key (@{$$opts{SN_keys}})
                {
                    next unless exists $$opts{dat}{$id}{$key};
                    print $fh "SN\t$id\t$key\t$$opts{dat}{$id}{$key}\n";
                }
            }
        }
    }
}
