use v6.d;
unit module Audio::Midi::Raw:ver<0.0.1>:auth<samgwise>;

use Numeric::Pack :ALL;

=begin pod

=head1 Audio::Midi::Raw

Mappable - a primitive interface to simple MIDI files

=head1 SYNOPSIS

  use Audio::Midi::Raw;

=head1 DESCRIPTION

=head1 AUTHOR

Sam Gillespie <samgwise@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2020 Sam Gillespie

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

our constant opus-header = Buf.new(|"MThd".encode('ascii')[]);
our constant track-header = Buf.new(|"MTrk".encode('ascii')[]);

# Status messages from: https://www.midi.org/specifications/item/table-1-summary-of-midi-message

# Channel message codes, the tailing 4 bits define the channel
our constant note-off           = 0b1000_0000;
our constant note-on            = 0b1001_0000;
our constant poly-preassure     = 0b1010_0000; # Polyphonic aftertouch
our constant control-change     = 0b1011_0000; # Also used with Channel Mode Messages
our constant program-change     = 0b1100_0000;
our constant channel-preassure  = 0b1101_0000; # channel wide aftertouch
our constant pitch-bend         = 0b1110_0000;

# Variations of the tailing 4 bits control the rest of the message pathing
our constant system-exclusive   = 0b1111_0000;

# Misc. commonly used values
constant NullByte = Buf.new(0x0);

#
# Event class wrappers
#

our role Event {
    method encode(UInt:D $channel --> Buf) { ... }
}

our class NoteOff does Event {
    has UInt $.note is required;
    has UInt $.velocity = 60;

    method encode(UInt:D $channel --> Buf) {
        Buf.new(note-off +| $channel, $!note, $!velocity)
    }
}

our sub note-off(UInt $note, UInt $velocity --> NoteOff) is export {
    NoteOff.new(:$note, :$velocity)
}

our class NoteOn does Event {
    has UInt $.note is required;
    has UInt $.velocity = 60;

    method encode(UInt:D $channel --> Buf) {
        Buf.new(note-on +| $channel, $!note, $!velocity)
    }
}

our sub note-on(UInt $note, UInt $velocity --> NoteOn) is export {
    NoteOn.new(:$note, :$velocity)
}

our class DeltaEvent {
    has UInt $.delta is required;
    has Event $.event is required;

    method encode(UInt:D $channel --> Buf) {
        pack-ber($!delta) ~ $!event.encode($channel)
    }
}

our sub delta(UInt $delta, Event $event) is export {
    DeltaEvent.new(:$delta, :$event)
}

our class Track {
    has DeltaEvent @.events;

    method encode(UInt $channel --> Buf) {
        my $encoded-events = [~] (.encode($channel) ~ NullByte for @!events);
        track-header
            ~ pack-uint32($encoded-events.bytes, :byte-order(big-endian))
            ~ $encoded-events
    }
}

our sub smf-track(*@events --> Track) is export {
    Track.new(:@events)
}

our sub opus(@tracks, UInt :$ticks = 96, Int :$format = 1 --> Buf) {
    opus-header
        ~ pack-uint32(6,                :byte-order(big-endian)) # 6 bytes following
        ~ pack-uint16($format,          :byte-order(big-endian))
        ~ pack-uint16(@tracks.elems,    :byte-order(big-endian))
        ~ pack-uint16($ticks,           :byte-order(big-endian))
        ~ ([~] .encode(@tracks.elems) for @tracks)
}