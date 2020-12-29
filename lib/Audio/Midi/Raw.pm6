use v6.d;
unit module Audio::Midi::Raw:ver<0.0.1>:auth<samgwise>;

use Numeric::Pack :ALL;

=begin pod

=head1 Audio::Midi::Raw

Audio::Midi::Raw - a primitive interface to simple MIDI files

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
our constant system-reset = 0b1111_1111;

# Misc. commonly used values
constant NullByte = Buf.new(0x0);
constant LittleNibble = 0b0000_1111;
constant BigNibble = 0b1111_0000;

sub is-event(UInt:D $control, $event --> Bool) {
    $control == ($event +& BigNibble)
}

#
# Event class wrappers
#

our role Event {
    method encode(UInt:D $channel --> Buf) { ... }

    method decode(Buf $data --> Event) { ... }
}

our class CustomEvent does Event {
    has &.encode is required;

    our sub generic-decode($data) { CustomEvent.new( :encode({ $data }) ) }
    has &.decode = &generic-decode;

    #= Default decode method reflects the given data as the encode method of a CustomeEvent

    method encode(UInt:D $channel --> Buf) {
        &!encode.($channel)
    }

    method decode(Buf $data --> Event) {
        &!decode.($data)
    }
}

our constant system-reset-event = CustomEvent.new(
    :encode({ Buf.new(system-reset) })
);

sub decode-note-event(Buf $data --> Map) {
    %(
        :channel($data[0] +& LittleNibble),
        :note($data[1]),
        :velocity($data[2])
    )
}

our class NoteOff does Event {
    has UInt $.note is required;
    has UInt $.velocity = 60;
    has UInt $.channel;

    multi method encode(UInt:D $channel --> Buf) {
        Buf.new(note-off +| $channel, $!note, $!velocity)
    }

    multi method encode( --> Buf) {
        Buf.new(note-off +| $!channel, $!note, $!velocity)
    }

    method decode(Buf $data --> NoteOff) {
        $?CLASS.new( |decode-note-event($data) )
    }
}

our sub note-off(UInt $note, UInt $velocity --> NoteOff) is export {
    NoteOff.new(:$note, :$velocity)
}

our class NoteOn does Event {
    has UInt $.note is required;
    has UInt $.velocity = 60;
    has UInt $.channel;

    multi method encode(UInt:D $channel --> Buf) {
        Buf.new(note-on +| $channel, $!note, $!velocity)
    }

    multi method encode( --> Buf) {
        Buf.new(note-on +| $!channel, $!note, $!velocity)
    }

    method decode(Buf $data --> NoteOn) {
        $?CLASS.new( |decode-note-event($data) )
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

    method decode(Buf $data --> DeltaEvent) {
        my $raw-delta = collect-ber($data);
        my $delta = unpack-ber($raw-delta);
        my $event = do given $data.subbuf($raw-delta.bytes) {
            when is-event(note-on, $_[0]) {
                NoteOn.decode($_)
            }
            when is-event(note-off, $_[0]) {
                NoteOff.decode($_)
            }
            default { CustomEvent::generic-decode($_) }
        }

        $?CLASS.new( :$delta, :$event);
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

    method decode(Buf $data --> List) {
        # Check data header
        return (Track).Slip unless $data.list.head(track-header.bytes) eqv track-header.list.Seq;

        my $track-length = unpack-uint32($data.subbuf(track-header.bytes, 4), :byte-order(big-endian));
        my $header-length = track-header.bytes + 4;
        # say "pasrsing track of $track-length bytes";

        # Decode events stream
        my Track $track .= new;
        my $last-index = $header-length;
        for ($header-length)..($track-length + $header-length) -> $i {
            next if $i == $last-index;
            # say "$i => $data[$i]";
            if $data[$i] == 0x0 {
                #say $data.subbuf($last-index, $i).perl;
                $track.events.push: DeltaEvent.decode($data.subbuf($last-index, $i));
                $last-index = $i + 1;
            }
        }

        # Call recursivly if there is still data remaining
        $track, |(track-header.bytes > $header-length + $track-length
            ?? $?CLASS.decode($data.subbuf($header-length + $track-length))
            !! ()
        )
    }
}

our sub smf-track(*@events --> Track) is export {
    Track.new(:@events)
}

our sub opus(@tracks, UInt :$ticks = 96 --> Buf) is export {
    my $track-count = @tracks.elems;
    my $format = ($track-count == 1 ?? 0 !! 1);

    reduce { $^a.push: $^b[] }, 
    opus-header.subbuf(0) # use subbuff to copy the data to a new writable buffer
        , pack-uint32(6,                :byte-order(big-endian)) # 6 bytes following
        , pack-uint16($format,          :byte-order(big-endian))
        , pack-uint16($track-count,     :byte-order(big-endian))
        , pack-uint16($ticks,           :byte-order(big-endian))
        , |([~] .encode($track-count)[] for @tracks).list
}

our sub decode-opus(Buf $data --> List) is export {
    # Return undefined if the header is missing
    return (Track).Slip unless $data.list.head(opus-header.bytes) eqv opus-header.list.Seq;

    my $header-length = unpack-uint32($data.subbuf(opus-header.bytes, 4), :byte-order(big-endian));
    # Read shorts for length of header (kind of assuming only 3 for now)
    my ($format, $track-count, $ticks, *@) = do for 0..^($header-length div 2) {
        unpack-uint16($data.subbuf(opus-header.bytes+ 4 + ($_ * 2), 2), :byte-order(big-endian));
    }

    Track.decode($data.subbuf(opus-header.bytes + 4 + $header-length))
}