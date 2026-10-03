[CCode (cheader_filename = "pulse/operation.h")]
namespace PulseAudio {
    [CCode (cname = "pa_operation_notify_cb_t")]
    public delegate void OperationNotifyCb (Operation operation);
    [CCode (cname = "pa_operation_set_state_callback")]
    public static void operation_set_state_callback (Operation operation, OperationNotifyCb? cb);
}
