#! /usr/bin/env perl6
use v6.d;
use Audio::Midi::Raw;

my $midi-out = "temp/test.mid";

my $opus = opus([
    smf-track(
        delta(0, note-on(60, 60)),
        delta(192, note-off(60, 60)),
    ),
]);

say "Generated { $opus.list.elems } bytes:";
$opus.list.rotor(4, :partial).map( { .fmt("%02X", ' ') } ).join("\n").say;

$midi-out.IO.spurt($opus, :bin);

say "Written:";

$midi-out.IO.slurp(:bin).list.rotor(4, :partial).map( { .fmt("%02X", ' ') } ).join("\n").say;