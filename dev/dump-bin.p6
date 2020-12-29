#! /usr/bin/env perl6
use v6.d;

sub MAIN($file, :$width = 4);

my $bin = $file.IO.slurp(:bin);
say "--- start of $file { $bin.bytes } bytes long ---";

$bin.list.rotor(4, :partial).map( { .fmt("%02X", ' ') } ).join("\n").say;

say "--- end of $file { $bin.bytes } bytes long ---";