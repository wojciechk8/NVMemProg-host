/*
 * Copyright (C) 2017 Wojciech Krutnik <wojciechk8@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */
  

public class MemoryAction {
  MemoryDevice device;
  MemoryDeviceConfig config;
  NVMemProgDevice nvmemprog;
  Gtk.Window parent_window;
  Dialog dialog;
  Cancellable? cancellable;
  bool overcurrent;
  ulong overcurrent_hadler_id;
  SourceFunc action_close_callback;
  const int POWER_UP_DELAY = 80;
  const uint UPDATE_TRANSFER_INTERVAL = 300;
  
  public enum Type {
    READ_ID,
    READ,
    WRITE
  }
  
  
  private class Dialog : Gtk.Dialog {
    private Gtk.Label status_label;
    private TransferBox transfer_box;
    private Gtk.ProgressBar progressbar;
    private Gtk.Button abort_button;
    private Gtk.Button close_button;
    private Gtk.Expander log_expander;
    private Gtk.TextView log_view;
    private Gtk.TextIter log_iter;
    private Timer timer;
    private uint transfer_timeout_id;
    private uint activity_timeout_id;
    private NVMemProgDevice nvmemprog;
    private uint64 memory_size;
    private const int DIALOG_WIDTH = 430;
    private const int DIALOG_HEIGHT = 80;
    
    private class TransferBox : Gtk.Grid {
      private NVMemProgDevice nvmemprog;
      private Timer timer;
      private uint64 size;
      private uint64 last_transferred;
      private double last_time;
      private bool started;
      private Gtk.Label speed_label;
      private Gtk.Label transferred_label;
      private Gtk.Label remaining_time_label;
      private Gtk.Label remaining_time_label_t;
      
      public TransferBox (NVMemProgDevice nvmemprog, uint64 memory_size) {
        this.nvmemprog = nvmemprog;
        size = memory_size;
        timer = new Timer ();
        started = false;
        
        var speed_label_t = new Gtk.Label ("Speed: ");
        speed_label_t.set_xalign (1);
        this.attach (speed_label_t, 0, 0);
        speed_label = new Gtk.Label (null);
        speed_label.set_use_markup (true);
        speed_label.set_xalign (0);
        this.attach (speed_label, 1, 0);
        
        var transferred_label_t = new Gtk.Label ("Transferred: ");
        transferred_label_t.set_xalign (1);
        this.attach (transferred_label_t, 0, 1);
        transferred_label = new Gtk.Label (null);
        transferred_label.set_use_markup (true);
        transferred_label.set_xalign (0);
        this.attach (transferred_label, 1, 1);
        
        remaining_time_label_t = new Gtk.Label ("Remaining time: ");
        remaining_time_label_t.set_xalign (1);
        this.attach (remaining_time_label_t, 0, 2);
        remaining_time_label = new Gtk.Label (null);
        remaining_time_label.set_use_markup (true);
        remaining_time_label.set_xalign (0);
        this.attach (remaining_time_label, 1, 2);
        
        update_transfer (false);
      }
      
      public void start_transfer_timer () {
        last_time = 0;
        last_transferred = 0;
        started = true;
        timer.start ();
      }
      
      public void update_transfer (bool end) {
        if (started) {
          double elapsed_time = timer.elapsed ();
          float speed;
          if (end)
            speed = nvmemprog.transferred / (float) elapsed_time;
          else
            speed = (nvmemprog.transferred - last_transferred) / ((float) elapsed_time - (float) last_time);
          last_time = elapsed_time;
          last_transferred = nvmemprog.transferred;
          // TODO: calculate remaining time based on an avarage speed, not the current one
          ulong remaining_time = (ulong) ((size - nvmemprog.transferred) / speed);
          speed_label.set_label ("<i>%s</i>".printf (speed_to_str (speed)));
          transferred_label.set_label ("<i>%s/%s</i>".printf (size_to_str (nvmemprog.transferred), size_to_str (size)));
          if (end) {
            remaining_time_label_t.set_label ("Elapsed time: ");
            remaining_time_label.set_label ("<i>%02lum %02lus</i>".printf (((ulong) elapsed_time)/60, ((ulong) elapsed_time)%60));
          } else
            remaining_time_label.set_label ("<i>%02lum %02lus</i>".printf (remaining_time/60, remaining_time%60));
        } else {
          speed_label.set_label ("<i>N/A</i>");
          transferred_label.set_label ("<i>N/A</i>");
          remaining_time_label.set_label ("<i>N/A</i>");
        }
      }
    }
    
    
    public Dialog (string title, Gtk.Window parent, bool show_transfer_box, NVMemProgDevice nvmemprog, uint64 memory_size) {
      this.nvmemprog = nvmemprog;
      this.memory_size = memory_size;
      set_title (title);
      set_transient_for (parent);
      set_modal (true);
      set_border_width (5);
      set_deletable (false);
      set_default_size (DIALOG_WIDTH, DIALOG_HEIGHT);
      
      Gtk.Box content = get_content_area () as Gtk.Box;
      status_label = new Gtk.Label (null);
      progressbar = new Gtk.ProgressBar ();
      log_expander = new Gtk.Expander ("Log messages");
      Gtk.ScrolledWindow log_scrolled = new Gtk.ScrolledWindow (null, null);
      log_view = new Gtk.TextView ();
      
      content.set_spacing (8);
        Gtk.Box hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Label title_label = new Gtk.Label ("<b>%s</b>".printf(title));
        title_label.set_use_markup (true);
        hbox.pack_start (title_label, false);
        hbox.pack_end (status_label, false);
      content.pack_start (hbox, false);
      
      if (show_transfer_box) {
        transfer_box = new TransferBox (nvmemprog, memory_size);
        content.pack_start (transfer_box, true, true, 0);
      }
      content.pack_start (progressbar, true, true, 0);
            log_view.set_editable (false);
            log_view.set_tabs (new Pango.TabArray.with_positions (2, true, Pango.TabAlign.LEFT, 250, Pango.TabAlign.LEFT, 325));
            log_view.buffer.create_tag ("timestamp", "style", Pango.Style.ITALIC);
            log_view.buffer.create_tag ("header", "underline", Pango.Underline.SINGLE);
            log_view.buffer.create_tag ("done", "foreground", "green");
            log_view.buffer.create_tag ("error", "foreground", "red");
            log_view.buffer.create_tag ("cancel", "foreground", "orange");
            log_view.buffer.get_end_iter (out log_iter);
            log_view.buffer.insert_with_tags_by_name (ref log_iter, "Message\tResult\tTimestamp", -1, "header");
            log_view.size_allocate.connect ( () => {
              Gtk.Adjustment adj = log_scrolled.vadjustment;
              adj.set_value (adj.get_upper ());
            } );
          log_scrolled.set_size_request (410, 180);
          log_scrolled.add (log_view);
        log_expander.activate.connect ( () => {
          if (log_expander.get_expanded ())
            resize (get_allocated_width (), DIALOG_HEIGHT);
        } );
        log_expander.add (log_scrolled);
      content.pack_start (log_expander, true, true, 0);
      
      abort_button = new Gtk.Button.from_icon_name ("gtk-cancel");
      abort_button.set_label ("Abort");
      add_action_widget (abort_button, Gtk.ResponseType.CANCEL);
      
      close_button = new Gtk.Button.from_icon_name ("gtk-close");
      close_button.set_label ("Close");
      close_button.set_sensitive (false);
      close_button.clicked.connect ( () => { destroy (); } );
      add_action_widget (close_button, Gtk.ResponseType.CLOSE);
      set_focus (abort_button);
      
      timer = new Timer ();
      reset_timestamp ();
      
      transfer_timeout_id = 0;
      activity_timeout_id = 0;
    }
    
    
    public void start_transfer_update () {
      transfer_timeout_id = Timeout.add (UPDATE_TRANSFER_INTERVAL, () => {
        transfer_box.update_transfer (false);
        progressbar.set_fraction ((float) nvmemprog.transferred / memory_size);
        return Source.CONTINUE;
      });
      transfer_box.start_transfer_timer ();
    }
    
    public void start_activity_update () {
      activity_timeout_id = Timeout.add (UPDATE_TRANSFER_INTERVAL, () => {
        progressbar.pulse ();
        return Source.CONTINUE;
      });
    }
    
    
    public void set_completed (bool done, bool cancelled = false) {
      if (cancelled)
        status_label.set_markup ("<span foreground='orange'>Aborted</span>");
      else
        status_label.set_markup (done ? "<span foreground='green'>Done</span>" : "<span foreground='red'>Error</span>");
      if (done)
        progressbar.set_fraction (1);
      else if (!cancelled)
        expand_log (true);
      if (transfer_timeout_id != 0) {
        transfer_box.update_transfer (true);
        Source.remove (transfer_timeout_id);
      }
      if (activity_timeout_id != 0)
        Source.remove (activity_timeout_id);
      abort_button.set_sensitive (false);
      close_button.set_sensitive (true);
      set_focus (close_button);
    }
    
    public void expand_log (bool expand) {
      log_expander.set_expanded (expand);
    }
    
    public void add_log_entry (string text) {
      log_view.buffer.insert (ref log_iter, "\n%s".printf (text), -1);
    }
    
    public void add_log_error (string text) {
      log_view.buffer.insert_with_tags_by_name (ref log_iter, "\nError: %s".printf(text), -1, "error");
    }
    
    public void submit_log_entry (bool done, bool cancelled = false) {
      double timestamp = timer.elapsed ();
      if (cancelled)
        log_view.buffer.insert_with_tags_by_name (ref log_iter, "\tcancelled", -1, "cancel");
      else
        log_view.buffer.insert_with_tags_by_name (ref log_iter, done ? "\tdone" : "\terror", -1, done ? "done" : "error");
      log_view.buffer.insert_with_tags_by_name (ref log_iter, "\t%02u:%02.1fs".printf((uint) timestamp/60, timestamp%60), -1, "timestamp");
    }
    
    public void submit_log_entry_with_text (string text) {
      double timestamp = timer.elapsed ();
      log_view.buffer.insert (ref log_iter, "\t%s".printf(text), -1);
      log_view.buffer.insert_with_tags_by_name (ref log_iter, "\t%02u:%02.1fs".printf((uint) timestamp/60, timestamp%60), -1, "timestamp");
    }
    
    public void reset_timestamp () {
      timer.start ();
    }
  }
  
  
  public MemoryAction (MemoryDevice device, MemoryDeviceConfig config, NVMemProgDevice nvmemprog, Gtk.Window parent_window) {
    this.device = device;
    this.config = config;
    this.nvmemprog = nvmemprog;
    this.parent_window = parent_window;
  }
  
  
  private void on_dialog_response (int response_id) {
    switch (response_id) {
      case Gtk.ResponseType.CANCEL:
        if (cancellable != null)
          cancellable.cancel ();
        break;
      case Gtk.ResponseType.CLOSE:
        nvmemprog.disconnect (overcurrent_hadler_id);
        action_close_callback ();
        break;
    }
  }
  
  private void init_dialog (string title, bool show_transfer_box) {
    overcurrent = false;
    cancellable = new Cancellable ();
    overcurrent_hadler_id = nvmemprog.overcurrent.connect ( () => {
      cancellable.cancel ();
      overcurrent = true;
    });
    try {
      dialog = new Dialog (title, parent_window, show_transfer_box, nvmemprog, device.get_size ());
    } catch (DBError e) { }
    dialog.response.connect (on_dialog_response);
    dialog.show_all ();
  }
  
  private void show_error (string error) {
    if (overcurrent) {
      dialog.submit_log_entry (false);
      dialog.add_log_error ("Overcurrent!");
      dialog.set_completed (false);
    } else if (cancellable.is_cancelled ()) {
      dialog.submit_log_entry (false, true);
      dialog.add_log_error ("Aborted");
      dialog.set_completed (false, true);
    } else {
      dialog.submit_log_entry (false);
      dialog.add_log_error (error);
      dialog.set_completed (false);
    }
  }

  
  private async void init_action (Type action_type) throws UsbError, DBError, IOError {
    if (nvmemprog.is_fpga_configured ()) {
      dialog.add_log_entry ("FPGA is already configured");
    } else {
      dialog.add_log_entry ("Configuring FPGA...");
      Idle.add (init_action.callback); yield;
      uint8[] rbf_data = device.get_fpga_module_rbf_data ();
      nvmemprog.configure_fpga (rbf_data);
      dialog.submit_log_entry (true);
    }
    dialog.add_log_entry ("Configuring FPGA registers...");
    config.configure_fpga_registers ();
    dialog.submit_log_entry (true);
    dialog.add_log_entry ("Configuring memory interface...");
    config.configure_interface ();
    dialog.submit_log_entry (true);
    dialog.add_log_entry ("Configuring driver...");
    config.configure_driver (action_type);
    dialog.submit_log_entry (true);
    dialog.add_log_entry ("Enabling driver...");
    nvmemprog.enable_driver ();
    dialog.submit_log_entry (true);
    dialog.add_log_entry ("Setting current limit...");
    nvmemprog.set_icc (config.icc);
    if (config.vpp != 0)
      nvmemprog.set_ipp (config.ipp);
    dialog.submit_log_entry (true);
    dialog.add_log_entry ("Switching power on (Vcc)...");
    nvmemprog.switch_vcc (true);
    dialog.submit_log_entry (true);
    if ((action_type == Type.WRITE) && (config.vcc_prog != 0)) {
      dialog.add_log_entry ("Raising voltage (Vcc to Vcc_prog)...");
      nvmemprog.set_vcc (config.vcc_prog, config.vcc_rate);
    } else {
      dialog.add_log_entry ("Raising voltage (Vcc)...");
      nvmemprog.set_vcc (config.vcc, config.vcc_rate);
    }
    if (cancellable != null) cancellable.set_error_if_cancelled ();
    dialog.submit_log_entry (true);
    if (((action_type == Type.WRITE) && (config.vpp != 0))
        || ((action_type == Type.READ_ID) && (config.vid != 0))) {
      dialog.add_log_entry ("Switching power on (Vpp)...");
      nvmemprog.switch_vpp (true);
      dialog.submit_log_entry (true);
      if ((action_type == Type.WRITE) && (config.vpp != 0)) {
        dialog.add_log_entry ("Raising voltage (Vpp)...");
        nvmemprog.set_vpp (config.vpp, config.vpp_rate);
      } else if ((action_type == Type.READ_ID) && (config.vid != 0)) {
        dialog.add_log_entry ("Raising voltage (Vpp to Vid)...");
        nvmemprog.set_vpp (config.vid, config.vpp_rate);
      }
      if (cancellable != null) cancellable.set_error_if_cancelled ();
      dialog.submit_log_entry (true);
    }
    Timeout.add (POWER_UP_DELAY, () => { init_action.callback (); return Source.REMOVE; } ); yield;
    dialog.add_log_entry ("Resetting memory interface...");
    nvmemprog.abort_memory_operation ();
    dialog.submit_log_entry (true);
  }
  
  
  private async void finish_action () {
    try {
      dialog.add_log_entry ("Aborting memory operation...");
      nvmemprog.abort_memory_operation ();
      dialog.submit_log_entry (true);
    } catch (Error e) {
      dialog.submit_log_entry (false);
      dialog.add_log_error (e.message);
    }
    try {
      dialog.add_log_entry ("Switching power off (Vpp)...");
      nvmemprog.switch_vpp (false);
      Timeout.add (10, () => { finish_action.callback (); return Source.REMOVE; } ); yield;
      dialog.submit_log_entry (true);
    } catch (Error e) {
      dialog.submit_log_entry (false);
      dialog.add_log_error (e.message);
    }
    try {
      dialog.add_log_entry ("Switching power off (Vcc)...");
      nvmemprog.switch_vcc (false);
      dialog.submit_log_entry (true);
    } catch (Error e) {
      dialog.submit_log_entry (false);
      dialog.add_log_error (e.message);
    }
    try {
      dialog.add_log_entry ("Resetting DAC...");
      nvmemprog.reset_power ();
      dialog.submit_log_entry (true);
    } catch (Error e) {
      dialog.submit_log_entry (false);
      dialog.add_log_error (e.message);
    }
    try {
      dialog.add_log_entry ("Disabling driver...");
      nvmemprog.disable_driver ();
      dialog.submit_log_entry (true);
    } catch (Error e) {
      dialog.submit_log_entry (false);
      dialog.add_log_error (e.message);
    }
    dialog.add_log_entry ("");
    Timeout.add (POWER_UP_DELAY, () => { finish_action.callback (); return Source.REMOVE; } ); yield;
  }
  
  
  private string format_id (uint8[] id) {
    string res;
    res = "0x";
    foreach (uint8 byte in id)
      res += "%02hhX".printf (byte);
    return res;
  }
  
  private async bool read_id_priv () throws UsbError, DBError, IOError {
    uint8[]? expected_id;
    uint8[] actual_id;
    bool id_ok = true;
    
    expected_id = device.get_manufacturer_code ();
    if (expected_id != null) {
      dialog.add_log_entry ("Reading Manufacturer Id...");
      actual_id = yield nvmemprog.read_memory_id (NVMemProg.InterfaceIdType.MANUFACTURER, expected_id.length, cancellable);
      if (cancellable != null) cancellable.set_error_if_cancelled ();
      dialog.submit_log_entry_with_text (format_id (actual_id));
      if (Memory.cmp (actual_id, expected_id, expected_id.length) != 0) {
        dialog.add_log_error ("Manufacturer Id mismatch (expected %s)".printf (format_id (expected_id)));
        id_ok = false;
      }
    }
    expected_id = device.get_device_code ();
    if (expected_id != null) {
      dialog.add_log_entry ("Reading Device Id...");
      actual_id = yield nvmemprog.read_memory_id (NVMemProg.InterfaceIdType.DEVICE, expected_id.length, cancellable);
      if (cancellable != null) cancellable.set_error_if_cancelled ();
      dialog.submit_log_entry_with_text (format_id (actual_id));
      if (Memory.cmp (actual_id, expected_id, expected_id.length) != 0) {
        dialog.add_log_error ("Device Id mismatch (expected %s)".printf (format_id (expected_id)));
        id_ok = false;
      }
    }
    expected_id = device.get_extended_code ();
    if (expected_id != null) {
      dialog.add_log_entry ("Reading Extended Id...");
      actual_id = yield nvmemprog.read_memory_id (NVMemProg.InterfaceIdType.EXTENDED, expected_id.length, cancellable);
      if (cancellable != null) cancellable.set_error_if_cancelled ();
      dialog.submit_log_entry_with_text (format_id (actual_id));
      if (Memory.cmp (actual_id, expected_id, expected_id.length) != 0) {
        dialog.add_log_error ("Extended Id mismatch (expected %s)".printf (format_id (expected_id)));
        id_ok = false;
      }
    }
    return id_ok;
  }
  
  public async void read_id () {
    bool id_ok;
    action_close_callback = read_id.callback;
    init_dialog ("Read ID", false);
    dialog.expand_log (true);
    try {
      yield init_action (Type.READ_ID);
      id_ok = yield read_id_priv ();
      yield finish_action ();
      dialog.set_completed (id_ok);
    } catch (Error e) {
      show_error (e.message);
      yield finish_action ();
    }
    yield;
  }
  
  public async void read_data (OutputStream data_stream) {
    bool id_ok;
    action_close_callback = read_data.callback;
    init_dialog ("Read Data", true);
    try {
      yield init_action (Type.READ_ID);
      id_ok = yield read_id_priv ();
      yield finish_action ();
      if (id_ok) {
        yield init_action (Type.READ);
        dialog.add_log_entry ("Reading memory data...");
        dialog.start_transfer_update ();
        yield nvmemprog.read_memory_data (data_stream, device.get_size (), cancellable);
        dialog.submit_log_entry (true);
        yield finish_action ();
      }
      dialog.set_completed (id_ok);
    } catch (Error e) {
      show_error (e.message);
      yield finish_action ();
    }
    yield;
  }
  
  public async void write_data (InputStream data_stream) {
    bool id_ok;
    action_close_callback = write_data.callback;
    init_dialog ("Write Data", true);
    try {
      yield init_action (Type.READ_ID);
      id_ok = yield read_id_priv ();
      yield finish_action ();
      id_ok = true;
      if (id_ok) {
        yield init_action (Type.WRITE);
        dialog.add_log_entry ("Writing memory data...");
        dialog.start_transfer_update ();
        yield nvmemprog.write_memory_data (data_stream, device.get_size (), cancellable);
        dialog.submit_log_entry (true);
        yield finish_action ();
      }
      dialog.set_completed (id_ok);
    } catch (Error e) {
      show_error (e.message);
      yield finish_action ();
    }
    yield;
  }
  
  public async void verify_data (InputStream data_stream) {
    bool id_ok, verify_ok = false;
    uint64 error_offset = 0;
    action_close_callback = verify_data.callback;
    init_dialog ("Verify Data", true);
    try {
      yield init_action (Type.READ_ID);
      id_ok = yield read_id_priv ();
      yield finish_action ();
      if (id_ok) {
        yield init_action (Type.READ);
        dialog.add_log_entry ("Verifying memory data...");
        dialog.start_transfer_update ();
        verify_ok = yield nvmemprog.verify_memory_data (data_stream, device.get_size (), &error_offset, cancellable);
        if (verify_ok) {
          dialog.submit_log_entry (true);
        } else {
          dialog.submit_log_entry (false);
          dialog.add_log_error ("Data mismatch at offset: 0x%08llx".printf (error_offset));
        }
        yield finish_action ();
      }
      dialog.set_completed (id_ok && verify_ok);
    } catch (Error e) {
      show_error (e.message);
      yield finish_action ();
    }
    yield;
  }
  
  public async void erase_chip () {
    bool id_ok, erased = false;
    action_close_callback = erase_chip.callback;
    init_dialog ("Chip Erase", false);
    try {
      yield init_action (Type.READ_ID);
      id_ok = yield read_id_priv ();
      yield finish_action ();
      if (id_ok) {
        yield init_action (Type.WRITE);
        dialog.add_log_entry ("Erasing memory...");
        dialog.start_activity_update ();
        erased = yield nvmemprog.erase_chip (device.get_chip_erase_time () * 1000, cancellable);
        if (erased)
          dialog.submit_log_entry (true);
        else {
          dialog.submit_log_entry (false);
          dialog.add_log_error ("Timeout expired");
        }
        yield finish_action ();
      }
      dialog.set_completed (id_ok && erased);
    } catch (Error e) {
      show_error (e.message);
      yield finish_action ();
    }
    yield;
  }
  
  public async void blank_check () {
    bool id_ok, checked_ok = false;
    uint64 error_offset = 0;
    action_close_callback = blank_check.callback;
    init_dialog ("Blank Check", true);
    try {
      yield init_action (Type.READ_ID);
      id_ok = yield read_id_priv ();
      yield finish_action ();
      if (id_ok) {
        yield init_action (Type.READ);
        dialog.add_log_entry ("Blank checking...");
        dialog.start_transfer_update ();
        checked_ok = yield nvmemprog.blank_check (device.get_size (), &error_offset, cancellable);
        if (checked_ok)
          dialog.submit_log_entry (true);
        else {
          dialog.submit_log_entry (false);
          dialog.add_log_error ("Memory is not blank; error at offset: 0x%08llx".printf (error_offset));
        }
        yield finish_action ();
      }
      dialog.set_completed (id_ok && checked_ok);
    } catch (Error e) {
      show_error (e.message);
      yield finish_action ();
    }
    yield;
  }
}
