[CCode (cheader_filename = "Backends/speaker-equalizer-profile.h")]
namespace SpeakerEqualizerProfile {
    [CCode (cname = "eq_profile_read")]
    public string read (string id) throws GLib.FileError;
}
