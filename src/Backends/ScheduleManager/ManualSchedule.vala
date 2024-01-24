public class SettingsDaemon.Backends.ManualSchedule : Schedule {
    public double from { get; construct set; }
    public double to { get; construct set; }

    public ManualSchedule (string name, double from, double to) {
        base ();
        this.name = name;
        this.from = from;
        this.to = to;
    }

    public ManualSchedule.from_parsed (Parsed parsed) {
        base.from_parsed (parsed);
        from = (double) parsed.args["from"];
        to = (double) parsed.args["to"];
    }

    construct {
        Timeout.add (1000, time_callback);
    }

    private bool time_callback () {
        var is_in = is_in_time_window ();

        if (active != is_in) {
            active = is_in;
        }

        return Source.CONTINUE;
    }

    private bool is_in_time_window () {
        var date_time = new DateTime.now_local ();
        double time_double = 0;
        time_double += date_time.get_hour ();
        time_double += (double) date_time.get_minute () / 60;

        // PM to AM
        if (from > to) {
            return time_double < to ? time_double <= from : time_double >= from;
        }

        // AM to AM, PM to PM, AM to PM
        return (time_double >= from && time_double <= to);
    }

    protected override HashTable<string, Variant> get_private_args () {
        var result = new HashTable<string, Variant> (str_hash, str_equal);
        result["from"] = from;
        result["to"] = to;
        return result;
    }
}
