use v6.d;
use Test;

use-ok 'Audio::Midi::Raw';
use Audio::Midi::Raw;

is-deeply note-on(60, 60).encode(0)[],  Buf.new(0b1001_0000, 60, 60)[], "Encode note on.";
is-deeply note-off(60, 60).encode(0)[], Buf.new(0b1000_0000, 60, 60)[], "Encode note off.";

# Track encoding
is-deeply
    smf-track(
        delta(0, note-on(60, 60)),
        delta(192, note-off(60, 60)),
    ).encode(0)[],
    Buf.new(
        |Audio::Midi::Raw::track-header[],
        0x00, 0x00, 0x00, 0x0B,                 # uint32 of value 10 signalling 10 bytes to following
        0x00, 0b1001_0000, 60, 60, 0x0,         # Immediate note on, null terminated
        0x81, 0x40, 0b1000_0000, 60, 60, 0x0,   # Delayed note off, null terminated
    )[],
    "Encode track";


done-testing;
