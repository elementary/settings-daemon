// Isolated production EchoProcessor runner; no EQ or desktop bus dependency.
int main (string[] args) {
    assert (Environment.get_variable ("AEC_PRIVATE_TEST") == "1");
    assert (!FileUtils.test ("/dev/snd", FileTest.EXISTS));
    assert (Environment.get_variable ("PULSE_SERVER").has_prefix ("unix:" + Environment.get_variable ("XDG_RUNTIME_DIR") + "/"));
    var settings = new Settings ("io.elementary.settings-daemon.audio");
    settings.set_boolean ("echo-cancellation", args[1] == "restore");
    var main_loop = new MainLoop ();
    var pulse_loop = new PulseAudio.GLibMainLoop ();
    var context = new PulseAudio.Context (pulse_loop.get_api (), "AEC isolated regression");
    SettingsDaemon.Backends.EchoProcessor? processor = null;
    context.set_state_callback ((c) => {
        if (c.get_state () == PulseAudio.Context.State.READY) {
            processor = new SettingsDaemon.Backends.EchoProcessor (c);
            c.set_subscribe_callback ((connection, event, index) => {
                var facility = event & PulseAudio.Context.SubscriptionEventType.FACILITY_MASK;
                if (facility == PulseAudio.Context.SubscriptionEventType.SERVER) {
                    processor.observe_defaults ();
                } else if (facility == PulseAudio.Context.SubscriptionEventType.MODULE &&
                    (event & PulseAudio.Context.SubscriptionEventType.TYPE_MASK) == PulseAudio.Context.SubscriptionEventType.REMOVE) {
                    processor.module_removed (index);
                } else {
                    processor.refresh ();
                }
            });
            c.subscribe (PulseAudio.Context.SubscriptionMask.SERVER | PulseAudio.Context.SubscriptionMask.SOURCE |
                PulseAudio.Context.SubscriptionMask.SINK | PulseAudio.Context.SubscriptionMask.MODULE,
                (connection, success) => {
                    assert (success == 1);
                    processor.observe_defaults ();
                });
        } else if (c.get_state () == PulseAudio.Context.State.FAILED) {
            main_loop.quit ();
        }
    });
    var input = new IOChannel.unix_new (0);
    input.add_watch (IOCondition.IN, (channel, condition) => {
        try {
            string line;
            channel.read_line (out line, null, null);
            settings.set_boolean ("echo-cancellation", line.strip () == "enable");
        } catch (Error e) {
            error (e.message);
        }
        return Source.CONTINUE;
    });
    Timeout.add (100, () => {
        if (processor != null) {
            stdout.printf ("%s %s %s %s %s\n", processor.enabled.to_string (), processor.available.to_string (),
                processor.busy.to_string (), settings.get_boolean ("echo-cancellation").to_string (), processor.error ?? "-");
            stdout.flush ();
        }
        return Source.CONTINUE;
    });
    context.connect (null, PulseAudio.Context.Flags.NOAUTOSPAWN);
    main_loop.run ();
    return 0;
}
