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

# Round trip test
{
    my $note-on = note-on(60, 60);
    is Audio::Midi::Raw::NoteOn.decode($note-on.encode(0)).note, $note-on.note, "note-on round trip";

    my $note-off = note-off(60, 60);
    is Audio::Midi::Raw::NoteOn.decode($note-off.encode(0)).velocity, $note-off.velocity, "note-off round trip";

    # Delta wrapped events
    my $delta-on = delta(0, $note-on);

    is Audio::Midi::Raw::DeltaEvent.decode($delta-on.encode(0)).delta, $delta-on.delta, "delta(note-on) round trip";
    is Audio::Midi::Raw::DeltaEvent.decode($delta-on.encode(0)).event.note, $delta-on.event.note, "delta(note-on) round trip (note)";

    my $delta-off = delta(4000, $note-off);

    is Audio::Midi::Raw::DeltaEvent.decode($delta-off.encode(0)).delta, $delta-off.delta, "delta(note-off) round trip";
    is Audio::Midi::Raw::DeltaEvent.decode($delta-off.encode(0)).event.note, $delta-off.event.note, "delta(note-off) round trip (note)";

    # Track round trip
    my $track = smf-track(
        $delta-on,
        $delta-off
    );

    is Audio::Midi::Raw::Track.decode($track.encode(0)).head.events.elems, $track.events.elems, "track(delta(note-on), ...) round trip";

    is Audio::Midi::Raw::Track.decode($track.encode(0)).head.events.tail.delta, $track.events.tail.delta, "track(delta(note-on), ...) round trip (delta)";

    is Audio::Midi::Raw::Track.decode($track.encode(0)).head.events.tail.event.note, $track.events.tail.event.note, "track(delta(note-on), ...) round trip (note)";

    # opus tests
    is decode-opus(opus([$track])).head.events.elems, $track.events.elems, "opus track(delta(note-on), ...) round trip";
}

done-testing;
