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


public string speed_to_str (float speed) {
  if (speed < 1024) {
    return "%.0f B/s".printf(speed);
  } else if (speed < 1024*1024) {
    return "%.2f kB/s".printf(speed/1024);
  } else {
    return "%.2f MB/s".printf(speed/(1024*1024));
  }
}

public string size_to_str (uint64 size) {
  string suffix;
  if (size < 1024) {
    suffix = "B";
  } else if (size < 1024*1024) {
    size /= 1024; suffix = "kB";
  } else if (size < 1024*1024*1024) {
    size /= 1024*1024; suffix = "MB";
  } else {
    size /= 1024*1024*1024; suffix = "GB";
  }
  return size.to_string () + suffix;
}


class NVMemProgApplication : Gtk.Application {
  private UsbInterface usb;
  private NVMemProgDevice nvmemprog;
  private DBManager db_manager;
  private const string DATABASE_FILENAME = "chips.db";
  private MemoryDevice mem_device;
  private MemoryDeviceConfig mem_config;
  private MemoryAction mem_action;
  
  private const string FIRMWARE_DIRECTORY = "firmware";
  private const string FIRMWARE_DEFAULT = "dummy";
  private const int FIRMWARE_LOAD_DELAY = 40;
  private string firmware_name;
  private uint connect_timeout_id;
  private bool loading_fw_after_connect;
  private Cancellable status_cancellable;
  
  private Gtk.Window window;
  
  private Gtk.SearchEntry device_filter_entry;
  private Gtk.TreeView device_treeview;
  private Gtk.TreeStore device_store;
  
  private DescriptionBox description_box;
  private Gtk.Notebook buffer_notebook;
  private SList<Buffer> buffer_list;
  private string buffer_font_name;
  private Pango.FontDescription buffer_font_desc;
  private Gtk.Statusbar statusbar;
  private uint statusbar_status_id;
  private Gtk.Label connection_label;
  private Gtk.Label signature_label;
  
  
  class ErrorMessage : Gtk.MessageDialog {
    public ErrorMessage (Gtk.Window parent, string msg_str, string console_str = "") {
      critical (console_str);
      var msg = new Gtk.MessageDialog (parent, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, msg_str);
      msg.run ();
      msg.destroy ();
    }
  }
  
  
  class DescriptionBox : Gtk.FlowBox {
    private Gtk.Label[] labels;
    private const string[] fields =
      {"Device", "Manufacturer", "Type", "Package", "Size", "Access Time", "Interface",
       "Vcc", "Vcc(prog)", "Vpp", "Icc", "Ipp"};
    
    public DescriptionBox () {
      labels = new Gtk.Label[fields.length];
      for (int i = 0; i < fields.length; i++) {
        labels[i] = new Gtk.Label (null);
        labels[i].set_selectable (true);
        this.add (labels[i]);
      }
      
      this.set_selection_mode (Gtk.SelectionMode.NONE);
      this.set_homogeneous (false);
      
      try { update (null); } catch (DBError e) { };
    }
    
    
    private string label_text (string attr, string? text) {
      return "<b>" + attr + ":</b> <i>" + (text ?? "N/A") + "</i>";
    }
    
    private string label_int (string attr, int num, string format = "") {
      return "<b>" + attr + ":</b> <i>" + (num != 0 ? num.to_string (format) : "N/A") + "</i>";
    }
    
    private string label_float (string attr, float num, string format = "") {
      return "<b>" + attr + ":</b> <i>" + (num != 0 ? num.to_string (format) : "N/A") + "</i>";
    }
    
    private string label_size (string attr, uint64 size) {
      return "<b>" + attr + ":</b> <i>" + (size != 0 ? size_to_str (size) : "N/A") + "</i>";
    }
    
    public void update (MemoryDevice? mem_device) throws DBError {
      labels[0].set_markup (label_text (fields[0], mem_device != null ? mem_device.get_name () : null));
      labels[1].set_markup (label_text (fields[1], mem_device != null ? mem_device.get_manufacturer () : null));
      labels[2].set_markup (label_text (fields[2], mem_device != null ? mem_device.get_dev_type () : null));
      labels[3].set_markup (label_text (fields[3], mem_device != null ? mem_device.get_package () + mem_device.get_pin_count ().to_string () : null));
      labels[4].set_markup (label_size (fields[4], mem_device != null ? mem_device.get_size () : 0));
      labels[5].set_markup (label_int (fields[5], mem_device != null ? mem_device.get_speed () : 0, "%dns"));
      labels[6].set_markup (label_text (fields[6], mem_device != null ? mem_device.get_interface_name () : null));
      labels[7].set_markup (label_float (fields[7], mem_device != null ? mem_device.get_vcc () : 0, "%.1fV"));
      labels[8].set_markup (label_float (fields[8], mem_device != null ? mem_device.get_vcc_prog () : 0, "%.1fV"));
      labels[9].set_markup (label_float (fields[9], mem_device != null ? mem_device.get_vpp () : 0, "%.1fV"));
      labels[10].set_markup (label_int (fields[10], mem_device != null ? mem_device.get_icc () : 0, "%dmA"));
      labels[11].set_markup (label_int (fields[11], mem_device != null ? mem_device.get_ipp () : 0, "%dmA"));
    }
  }
  
  private class BufferOutputStream : OutputStream {
    private Buffer buffer;
    private uint offset;
    
    public BufferOutputStream (Buffer buffer) {
      this.buffer = buffer;
      offset = 0;
    }
    
    public override bool close (Cancellable? cancellable = null) {
      return true;
    }
    
    public override ssize_t write (uint8[] buffer, Cancellable? cancellable = null) throws IOError {
      this.buffer.write (buffer, offset);
      offset += buffer.length;
      return buffer.length;
    }
    
    public override async ssize_t write_async (uint8[]? buffer, int io_priority = Priority.DEFAULT, Cancellable? cancellable = null) throws IOError {
      this.buffer.write (buffer, offset);
      offset += buffer.length;
      return buffer.length;
    }
  }
  
  private class BufferInputStream : InputStream {
    private Buffer buffer;
    private uint offset;
    
    public BufferInputStream (Buffer buffer) {
      this.buffer = buffer;
      offset = 0;
    }
    
    public override bool close (Cancellable? cancellable = null) {
      return true;
    }
    
    public override ssize_t read (uint8[] buffer, Cancellable? cancellable = null) throws IOError {
      this.buffer.read (buffer, offset);
      offset += buffer.length;
      return buffer.length;
    }
    
    public override async ssize_t read_async (uint8[]? buffer, int io_priority = Priority.DEFAULT, Cancellable? cancellable = null) throws IOError {
      this.buffer.read (buffer, offset);
      offset += buffer.length;
      return buffer.length;
    }
  }
  
  private class Buffer {
    public const uint64 MAX_BUFFER_SIZE = 128*1024*1024;
    
    public HexDocument hexdoc;
    public GtkHex hexview;
    
    public string name { get; private set; }
    public string? filename { get; private set; }
    public uint64 size { get; private set; }
    public bool changed { get; private set; }
    public bool is_new { get; private set; }
    public bool is_big { get; private set; }
    
    
    public Buffer (uint64 size) {
      if (size <= MAX_BUFFER_SIZE) {
        hexdoc = new HexDocument ();
        uint8[] data = new uint8[size];
        Memory.set (data, 0xFF, (size_t) size);
        hexdoc.set_data (0, 0, data, false);
        hexview = (GtkHex) hexdoc.add_view ();
        hexdoc.document_changed.connect ( () => {
          changed = true;
          is_new = false;
        });
        is_big = false;
      } else {
        // TODO:
        // create temp file
        // transfer data directly between memory device and file
        // show label with information that mem size is too big, instead of hexview
        // same for Buffer.from_file, but use the file provided there
        is_big = true;
      }
      name = "<new buffer>";
      this.size = size;
      changed = false;
      is_new = true;
    }
    
    public Buffer.from_file (string filename, uint64 size) throws Error {
      File file = File.new_for_path(filename);
      int64 file_size = file.query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE).get_size ();
      hexdoc = new HexDocument ();
      uint8[] data = new uint8[size];
      var file_stream = file.read ();
      var data_stream = new DataInputStream (file_stream);
      data_stream.read (data[0 : uint64.min (size, file_size)]);
      if (file_size < size) {
        Memory.set (data[file_size : size], 0xFF, (size_t) (size - file_size));
      }
      hexdoc.set_data (0, 0, data, false);
      hexview = (GtkHex) hexdoc.add_view ();
      hexdoc.document_changed.connect ( () => {
          changed = true;
        });
      this.size = size;
      changed = size != file_size;
      name = Path.get_basename (filename);
      this.filename = filename;
      is_new = false;
    }
    
    public OutputStream get_out_stream () {
      return new BufferOutputStream (this);
      if (is_big == false) {
        return new BufferOutputStream (this);
      } else {
        // TODO
        //return new FileOutputStream ();
      }
    }
    
    public InputStream get_in_stream () {
      return new BufferInputStream (this);
      if (is_big == false) {
        return new BufferInputStream (this);
      } else {
        // TODO
        //return new FileOutputStream ();
      }
    }
    
    public void save (string filename) throws Error {
      Posix.FILE? file = Posix.FILE.open (filename, "w");
      if (file == null) {
        throw new FileError.FAILED (Posix.strerror (Posix.errno));
      }
      if (hexdoc.write_to_file (file) != true) {
        throw new FileError.FAILED (Posix.strerror (Posix.errno));
      }
      this.filename = filename;
      name = Path.get_basename (filename);
      changed = false;
      is_new = false;
    }
    
    public void write (uint8[] data, uint offset)
      requires (data.length + offset <= size)
    {
      hexdoc.set_data (offset, data.length, data, false);
    }
    
    public void read (uint8[] data, uint offset)
      requires (data.length + offset <= size)
    {
      uint8[] temp;
      temp = hexdoc.get_data (offset, data.length);
      Memory.copy (data, temp, data.length);
    }
  }


  private enum DeviceTreeDepth {
    TYPE = 1,
    NAME = 2,
    VARIANT = 3
  }
  
  private enum DeviceTreeColumn {
    ID = 0,
    NAME = 1
  }
  
  private static bool version = false;
  private const GLib.OptionEntry[] options = {
    { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null },
    { null }  // list terminator
  };
  
  
  
  public NVMemProgApplication () {
    Object (application_id: "org.nvmemprog.application");
    mem_device = null;
    firmware_name = FIRMWARE_DEFAULT;
    buffer_font_name = "Monospace 8";
    buffer_font_desc = Pango.FontDescription.from_string (buffer_font_name);
  }
  
  
  private bool compare_device_name_with_filter (Gtk.TreeModel model, Gtk.TreeIter iter) {
    Value device_name;
    model.get_value (iter, DeviceTreeColumn.NAME, out device_name);

    if (device_filter_entry.get_text ().down () in device_name.get_string ().down ()){
      return true;
    }
    else{
      return false;
    }
  }
  
  
  private bool filter_device_func (Gtk.TreeModel model, Gtk.TreeIter iter) {
    if (device_filter_entry.get_text () == "")
      return true;
    
    DeviceTreeDepth depth = (DeviceTreeDepth) model.get_path (iter).get_depth ();
    switch (depth) {
      case DeviceTreeDepth.TYPE:
        return true;  // always visible
      
      case DeviceTreeDepth.NAME:
        Gtk.TreeIter child_iter;
        model.iter_children (out child_iter, iter);   // check if any variant matches the filter
        do {
          if (compare_device_name_with_filter (model, child_iter))
            return true;
        } while (model.iter_next (ref child_iter));
        return false;
      
      case DeviceTreeDepth.VARIANT:
        return compare_device_name_with_filter (model, iter);
      
      default:
        assert_not_reached();
    }
  }
  
  
  private void update_device_treeview_data () {
    Gtk.TreeIter type_iter, device_iter, variant_iter;
    MemoryDeviceList device_list = new MemoryDeviceList (db_manager);
    
    try {
      HashTable<int, string> types = device_list.get_device_types ();
      foreach (int id in types.get_keys ()) {
        device_store.append (out type_iter, null);
        device_store.set (type_iter, DeviceTreeColumn.ID, id, DeviceTreeColumn.NAME, types.get (id), -1);
      }
    } catch (DBError e) {
      new ErrorMessage (window, "Can't obtain device types from database",
                        "DB Error: %s".printf (e.message));
    }
    
    try {
      if (device_store.get_iter_first (out type_iter)) {
        do {
          Value type_id;
          device_store.get_value (type_iter, DeviceTreeColumn.ID, out type_id);
          HashTable<int, string> devices = device_list.get_devices ((int) type_id);
          foreach (int id in devices.get_keys ()) {
            device_store.append (out device_iter, type_iter);
            device_store.set (device_iter, DeviceTreeColumn.ID, id, DeviceTreeColumn.NAME, devices.get (id), -1);
          }
        } while (device_store.iter_next (ref type_iter));
      }
    } catch (DBError e) {
      Value type_name;
      device_store.get_value (type_iter, DeviceTreeColumn.NAME, out type_name);
      new ErrorMessage (window, "Can't obtain device variant list from database (DeviceType: %s)".printf ((string) type_name),
                        "DB Error: %s".printf (e.message));
    }
    
    try {
      if (device_store.get_iter_first (out type_iter)) {
        do {
          if (device_store.iter_children (out device_iter, type_iter)) {
            do {
              Value device_id;
              device_store.get_value (device_iter, DeviceTreeColumn.ID, out device_id);
              HashTable<int, string> variants = device_list.get_device_variants ((int) device_id);
              foreach (int id in variants.get_keys ()) {
                device_store.append (out variant_iter, device_iter);
                device_store.set (variant_iter, DeviceTreeColumn.ID, id, DeviceTreeColumn.NAME, variants.get (id), -1);
              }
            } while (device_store.iter_next (ref device_iter));
          }
        } while (device_store.iter_next (ref type_iter));
      }
    } catch (DBError e) {
      Value dev_name;
      device_store.get_value (device_iter, DeviceTreeColumn.NAME, out dev_name);
      new ErrorMessage (window, "Can't obtain device variant list from database (Device: %s)".printf ((string) dev_name),
                        "DB Error: %s".printf (e.message));
    }
  }
  
  
  private void setup_device_treeview () {
    device_store = new Gtk.TreeStore (2, typeof (int), typeof (string));
    
    device_store.set_sort_column_id (DeviceTreeColumn.NAME, Gtk.SortType.ASCENDING);

    // Headers setup
    // the first column is Id (not visible, so not adding to the device_treeview)
    device_treeview.insert_column_with_attributes (-1, "Name", new Gtk.CellRendererText (),
                                                   "text", DeviceTreeColumn.NAME, null);
    device_treeview.set_headers_visible (false);
    update_device_treeview_data ();

    // Filtering
    var filter = new Gtk.TreeModelFilter (device_store, null);
    filter.set_visible_func (filter_device_func);
    device_filter_entry.search_changed.connect (() => {
      filter.refilter ();
      if (device_filter_entry.get_text () == "")
        device_treeview.collapse_all ();
      else
        device_treeview.expand_all ();
    });
    device_treeview.set_search_entry (device_filter_entry);
    device_treeview.set_search_column (DeviceTreeColumn.NAME);
    
    device_treeview.set_model (filter);
  }
  
  
  private void setup_device_edit_buttons (Gtk.Box hbox) {
    Gtk.Button btn;
    
    btn = new Gtk.Button.from_icon_name ("gtk-add");
      btn.set_tooltip_text ("Add new device");
      btn.set_action_name ("device-edit.add");
      hbox.pack_start (btn);
    btn = new Gtk.Button.from_icon_name ("gtk-edit");
      btn.set_tooltip_text ("Edit selected device");
      btn.set_action_name ("device-edit.edit");
      hbox.pack_start (btn);
    btn = new Gtk.Button.from_icon_name ("gtk-remove");
      btn.set_tooltip_text ("Remove selected device");
      btn.set_action_name ("device-edit.remove");
      hbox.pack_start (btn);
  }
  
  
  private void update_device_edit_actions () {
    SimpleActionGroup group = (SimpleActionGroup) window.get_action_group ("device-edit");
    
    foreach (string action_str in group.list_actions ()) {
      (group.lookup_action (action_str) as SimpleAction).set_enabled (false);
    }
    
    Gtk.TreePath path;
    device_treeview.get_cursor (out path, null);
    
    if ((path == null) || (path.get_depth () == DeviceTreeDepth.VARIANT)) {
      return;
    } else if (path.get_depth () == DeviceTreeDepth.TYPE) {
      (group.lookup_action ("add") as SimpleAction).set_enabled (true);
    } else if (path.get_depth () == DeviceTreeDepth.NAME) {
      (group.lookup_action ("edit") as SimpleAction).set_enabled (true);
      (group.lookup_action ("remove") as SimpleAction).set_enabled (true);
    }
  }

  
  private void setup_buffer_toolbuttons (Gtk.Toolbar toolbar) {
    Gtk.Image img;
    Gtk.ToolButton btn;
    
    img = new Gtk.Image.from_icon_name ("document-new", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.ToolButton (img, null);
      btn.set_tooltip_text ("Create new buffer");
      btn.set_action_name ("buffer.new");
      toolbar.add (btn);
    img = new Gtk.Image.from_icon_name ("document-open", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.ToolButton (img, null);
      btn.set_tooltip_text ("Load buffer data from file");
      btn.set_action_name ("buffer.open");
      toolbar.add (btn);
    img = new Gtk.Image.from_icon_name ("document-save", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.ToolButton (img, null);
      btn.set_tooltip_text ("Save buffer data to file");
      btn.set_action_name ("buffer.save");
      toolbar.add (btn);
    img = new Gtk.Image.from_icon_name ("document-save-as", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.ToolButton (img, null);
      btn.set_tooltip_text ("Save buffer data to file");
      btn.set_action_name ("buffer.save-as");
      toolbar.add (btn);
    toolbar.add (new Gtk.SeparatorToolItem ());
    img = new Gtk.Image.from_icon_name ("gtk-close", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.ToolButton (img, null);
      btn.set_tooltip_text ("Close buffer");
      btn.set_action_name ("buffer.close");
      toolbar.add (btn);
    toolbar.add (new Gtk.SeparatorToolItem ());
    img = new Gtk.Image.from_icon_name ("preferences-desktop-font", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.ToolButton (img, null);
      btn.set_tooltip_text ("Change display font");
      btn.set_action_name ("buffer.font");
      toolbar.add (btn);
    btn = new Gtk.ToggleToolButton ();
      btn.set_tooltip_text ("Show/hide offsets");
      btn.set_action_name ("buffer.show-offset");
      btn.set_label ("O");
      toolbar.add (btn);
    toolbar.add (new Gtk.SeparatorToolItem ());
    btn = new Gtk.RadioToolButton (null);
      btn.set_tooltip_text ("Display data grouped by bytes");
      btn.set_label ("B");
      btn.set_action_name ("buffer.data-size");
      btn.set_action_target_value (new Variant.uint32 (GtkHex.GROUP_BYTE));
      toolbar.add (btn);
    btn = new Gtk.RadioToolButton.from_widget ((Gtk.RadioToolButton) btn);
      btn.set_tooltip_text ("Display data grouped by words");
      btn.set_action_name ("buffer.data-size");
      btn.set_action_target_value (new Variant.uint32 (GtkHex.GROUP_WORD));
      btn.set_label ("W");
    toolbar.add (btn);
    btn = new Gtk.RadioToolButton.from_widget ((Gtk.RadioToolButton) btn);
      btn.set_tooltip_text ("Display data grouped by dwords");
      btn.set_action_name ("buffer.data-size");
      btn.set_action_target_value (new Variant.uint32 (GtkHex.GROUP_DWORD));
      btn.set_label ("D");
      toolbar.add (btn);
  }
  
  private void update_buffer_actions () {
    SimpleActionGroup group = (SimpleActionGroup) window.get_action_group ("buffer");

    if (mem_device == null) {
      foreach (string action_str in group.list_actions ()) {
        (group.lookup_action (action_str) as SimpleAction).set_enabled (false);
      }
    } else {
      foreach (string action_str in group.list_actions ()) {
        (group.lookup_action (action_str) as SimpleAction).set_enabled (true);
      }
      if (buffer_list.length () == 0) {
        (group.lookup_action ("close") as SimpleAction).set_enabled (false);
        (group.lookup_action ("save") as SimpleAction).set_enabled (false);
        (group.lookup_action ("save-as") as SimpleAction).set_enabled (false);
      }
      if (buffer_notebook.get_current_page () > 0) {
        Buffer buffer = buffer_list.nth_data (buffer_notebook.get_current_page ());
        if (!buffer.changed) {
          (group.lookup_action ("save") as SimpleAction).set_enabled (false);
        }
      }
    }
  }
  
  private void append_buffer_hexview (Buffer buffer) {
    SimpleActionGroup group = (SimpleActionGroup) window.get_action_group ("buffer");
    buffer.hexview.set_font (GtkHex.load_font (buffer_font_name), buffer_font_desc);
    buffer.hexview.show_offsets (group.get_action_state ("show-offset").get_boolean ());
    buffer.hexview.set_geometry (16, 16);
    buffer_notebook.append_page (buffer.hexview, new Gtk.Label (buffer.name));
    buffer_notebook.show_all ();
    buffer_notebook.set_current_page ((int) buffer_list.length () - 1);
  }
  
  private bool can_close_buffer (Buffer buffer) {
    int response;
    if (buffer.changed) {
      var msg = new Gtk.MessageDialog (window, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO,
                                       "Buffer %s has been changed.\nDo you really want to close it without saving?".printf (buffer.name));
      response = msg.run ();
      msg.destroy ();
      if (response == Gtk.ResponseType.YES) {
        return true;
      } else {
        return false;
      }
    }
    return true;
  }
  
  private bool close_all_buffers () {
    SimpleActionGroup group = (SimpleActionGroup) window.get_action_group ("buffer");
    for (int i = (int) buffer_list.length (); i > 0; i--) {
      buffer_notebook.set_current_page (i - 1);
      group.activate_action ("close", null);
    }
    if (buffer_list.length () > 0) {
      return false;
    }
    return true;
  }
  
  private void action_buffer_new () {
    try {
      Buffer buffer = new Buffer (mem_device.get_size ());
      buffer_list.append (buffer);
      append_buffer_hexview (buffer);
      update_buffer_actions ();
    } catch (Error e) {
      new ErrorMessage (window, "Can't create new buffer");
    } 
  }

  private void action_buffer_open () {
    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
      "Open buffer from file", window, Gtk.FileChooserAction.OPEN,
      "_Cancel", Gtk.ResponseType.CANCEL,
      "_Open", Gtk.ResponseType.ACCEPT);
    chooser.response.connect ( (response) => {
        if (response == Gtk.ResponseType.ACCEPT) {
          Buffer current_buffer = buffer_list.nth_data (buffer_notebook.get_current_page ());
          if (current_buffer.is_new) {
            buffer_notebook.remove_page (buffer_list.index (current_buffer));
            buffer_list.remove (current_buffer);
          }
          try {
            File file = File.new_for_path(chooser.get_filename ());
            int64 file_size = file.query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE).get_size ();
            string? msg_str = null;
            if (file_size < mem_device.get_size ())
              msg_str = "File size is lower than memory device size.\nBuffer will be expanded to the memory device size.";
            if (file_size > mem_device.get_size ())
              msg_str = "File size is higher than memory device size.\nBuffer will be truncated to the memory device size.";
            if (msg_str != null) {
              var msg = new Gtk.MessageDialog (window, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.OK, msg_str);
              msg.run ();
              msg.destroy ();
            }
            Buffer buffer = new Buffer.from_file (chooser.get_filename (), mem_device.get_size ());
            buffer_list.append (buffer);
            append_buffer_hexview (buffer);
            update_buffer_actions ();
          } catch (Error e) {
            new ErrorMessage (window, "Error during opening buffer from file", e.message);
          }
        }
        chooser.destroy ();
      });
    chooser.run ();
  }

  private void action_buffer_save () {
    SimpleActionGroup group = (SimpleActionGroup) window.get_action_group ("buffer");
    int current_page = buffer_notebook.get_current_page ();
    Buffer buffer = buffer_list.nth_data (current_page);
    unowned string? filename = buffer_list.nth_data (current_page).filename;
    if (filename == null) {
      group.activate_action ("save-as", null);
    } else {
      try {
        buffer.save (filename);
        update_buffer_actions ();
      } catch (Error e) {
        new ErrorMessage (window, "Error during saving buffer to file", e.message);
      }
    }
  }
  
  private void action_buffer_save_as () {
    int current_page = buffer_notebook.get_current_page ();
    Buffer buffer = buffer_list.nth_data (current_page);
    Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
      "Save buffer to file", window, Gtk.FileChooserAction.SAVE,
      "_Cancel", Gtk.ResponseType.CANCEL,
      "_Save", Gtk.ResponseType.ACCEPT);
    chooser.set_do_overwrite_confirmation (true);
    chooser.set_current_name (buffer.is_new ? "buffer.bin" : buffer.name);
    chooser.response.connect ( (response) => {
        if (response == Gtk.ResponseType.ACCEPT) {
          try {
            buffer.save (chooser.get_filename ());
            buffer_notebook.set_tab_label_text (buffer.hexview, buffer.name);
            update_buffer_actions ();
          } catch (Error e) {
            new ErrorMessage (window, "Error during saving buffer to file", e.message);
          }
        }
        chooser.destroy ();
      });
    chooser.run ();
  }
  
  private void action_buffer_close () {
    int current_page = buffer_notebook.get_current_page ();
    if (can_close_buffer (buffer_list.nth_data (current_page))) {
      buffer_notebook.remove_page (current_page);
      buffer_list.remove (buffer_list.nth_data (current_page));
      update_buffer_actions ();
    }
  }

  private void action_buffer_font () {
    Buffer buffer = buffer_list.nth_data (buffer_notebook.get_current_page ());
    Gtk.FontChooserDialog chooser = new Gtk.FontChooserDialog ("Select buffer display font", window);
		chooser.response.connect ( (response) => {
        if (response == Gtk.ResponseType.OK) {
          buffer_font_name = chooser.get_font ();
          buffer_font_desc = chooser.get_font_desc ();
          buffer.hexview.set_font (GtkHex.load_font (buffer_font_name), buffer_font_desc);
        }
        chooser.destroy ();
      });
    chooser.run ();
  }

  private void action_buffer_show_offset_change (SimpleAction action, Variant? val) {
    action.set_state (val);
    foreach (unowned Buffer buf in buffer_list) {
      buf.hexview.show_offsets (val.get_boolean ());
    }
  }

  private void action_buffer_data_size_change (SimpleAction action, Variant? val) {
    action.set_state (val);
    foreach (unowned Buffer buf in buffer_list) {
      buf.hexview.set_group_type (val.get_uint32 ());
    }
  }
  
  
  private void setup_memory_action_buttons (Gtk.ButtonBox bbox) {
    //Gtk.Image img;
    Gtk.Button btn;
    
    //img = new Gtk.Image.from_icon_name ("document-new", Gtk.IconSize.SMALL_TOOLBAR);
    btn = new Gtk.Button ();
      btn.set_label ("Read ID"); btn.set_tooltip_text ("Read identification data from memory device");
      btn.set_action_name ("memory.read-id");
      bbox.add (btn);
    btn = new Gtk.Button ();
      btn.set_label ("Read"); btn.set_tooltip_text ("Read data from memory device to current buffer");
      btn.set_action_name ("memory.read");
      bbox.add (btn);
    btn = new Gtk.Button ();
      btn.set_label ("Verify"); btn.set_tooltip_text ("Verify memory device contents against current buffer contents");
      btn.set_action_name ("memory.verify");
      bbox.add (btn);
    btn = new Gtk.Button ();
      btn.set_label ("Write"); btn.set_tooltip_text ("Write data from current buffer to memory device");
      btn.set_action_name ("memory.write");
      bbox.add (btn);
    btn = new Gtk.Button ();
      btn.set_label ("Erase"); btn.set_tooltip_text ("Erase memory device contents");
      btn.set_action_name ("memory.erase");
      bbox.add (btn);
    btn = new Gtk.Button ();
      btn.set_label ("Blank Chk"); btn.set_tooltip_text ("Check if memory device is blank");
      btn.set_action_name ("memory.blank");
      bbox.add (btn);
    btn = new Gtk.Button ();
      btn.set_label ("Settings..."); btn.set_tooltip_text ("Device-specific settings");
      btn.set_action_name ("memory.settings");
      bbox.add (btn);
      bbox.set_child_secondary (btn, true);
    
    bbox.set_layout (Gtk.ButtonBoxStyle.START); bbox.set_spacing (12);
    bbox.set_margin_left (3); bbox.set_margin_right (3);
    bbox.set_margin_bottom (8);
  }
  
  
  private void update_memory_actions () {
    SimpleActionGroup group = (SimpleActionGroup) window.get_action_group ("memory");
    
    foreach (string action_str in group.list_actions ()) {
      (group.lookup_action (action_str) as SimpleAction).set_enabled (false);
    }
    
    if (mem_device == null) {
      return;
    }
    (group.lookup_action ("settings") as SimpleAction).set_enabled (true);
    if (!usb.is_connected) {
      return;
    }
    try {
      if (mem_device.get_has_read_id_capability ()) {
        (group.lookup_action ("read-id") as SimpleAction).set_enabled (true);
      }
      if (mem_device.get_has_read_capability ()) {
        (group.lookup_action ("read") as SimpleAction).set_enabled (true);
        (group.lookup_action ("verify") as SimpleAction).set_enabled (true);
        (group.lookup_action ("blank") as SimpleAction).set_enabled (true);
      }
      if (mem_device.get_has_write_capability ()) {
        (group.lookup_action ("write") as SimpleAction).set_enabled (true);
      }
      if (mem_device.get_has_erase_capability ()) {
        (group.lookup_action ("erase") as SimpleAction).set_enabled (true);
      }
    } catch (DBError e) {
      new ErrorMessage (window, "Can't obtain device capabilities", "DB Error: %s".printf (e.message));
    }
  }
  
  
  private void setup_actions (Gtk.Window win) {
    SimpleAction act;
    SimpleActionGroup group;
    
    group = new SimpleActionGroup ();
    (act = new SimpleAction ("add", null)).activate.connect (action_device_new); group.add_action (act);
    (act = new SimpleAction ("edit", null)).activate.connect (action_device_edit); group.add_action (act);
    (act = new SimpleAction ("remove", null)).activate.connect (action_device_remove); group.add_action (act);
    win.insert_action_group ("device-edit", group);
    
    group = new SimpleActionGroup ();
    (act = new SimpleAction ("new", null)).activate.connect (action_buffer_new); group.add_action (act);
    (act = new SimpleAction ("open", null)).activate.connect (action_buffer_open); group.add_action (act);
    (act = new SimpleAction ("save", null)).activate.connect (action_buffer_save); group.add_action (act);
    (act = new SimpleAction ("save-as", null)).activate.connect (action_buffer_save_as); group.add_action (act);
    (act = new SimpleAction ("close", null)).activate.connect (action_buffer_close); group.add_action (act);
    (act = new SimpleAction ("font", null)).activate.connect (action_buffer_font); group.add_action (act);
    (act = new SimpleAction.stateful ("show-offset", null, new Variant.boolean (true))).change_state.connect (action_buffer_show_offset_change); group.add_action (act);
    (act = new SimpleAction.stateful ("data-size", new VariantType("u"), new Variant.uint32 (GtkHex.GROUP_BYTE))).change_state.connect (action_buffer_data_size_change); group.add_action (act);
    win.insert_action_group ("buffer", group);
    
    group = new SimpleActionGroup ();
    (act = new SimpleAction ("read-id", null)).activate.connect (action_read_id); group.add_action (act);
    (act = new SimpleAction ("read", null)).activate.connect (action_read); group.add_action (act);
    (act = new SimpleAction ("verify", null)).activate.connect (action_verify); group.add_action (act);
    (act = new SimpleAction ("write", null)).activate.connect (action_write); group.add_action (act);
    (act = new SimpleAction ("erase", null)).activate.connect (action_erase); group.add_action (act);
    (act = new SimpleAction ("blank", null)).activate.connect (action_blank); group.add_action (act);
    (act = new SimpleAction ("settings", null)).activate.connect (action_settings); group.add_action (act);
    win.insert_action_group ("memory", group);
  }

  private void action_device_new () {
    
  }

  private void action_device_edit () {
    
  }

  private void action_device_remove () {
    
  }

  private void action_read_id () {
    if (check_firmware_signature (firmware_name) == false)
      if (load_firmware (firmware_name, false) == false)
        return;
    mem_action.read_id.begin ( (obj, res) => {
        mem_action.read_id.end (res);
    });
  }

  private void action_read () {
    Buffer buffer = buffer_list.nth_data (buffer_notebook.get_current_page ());
    if (buffer.changed) {
      var msg = new Gtk.MessageDialog (window, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO,
                                       "Buffer %s has been changed.\nDo you really want to overwrite the data?".printf (buffer.name));
      int response = msg.run ();
      msg.destroy ();
      if (response == Gtk.ResponseType.NO)
        return;
    }
    if (check_firmware_signature (firmware_name) == false)
      if (load_firmware (firmware_name, false) == false)
        return;
    mem_action.read_data.begin (buffer.get_out_stream (), (obj, res) => {
        mem_action.read_data.end (res);
    });
  }

  private void action_verify () {
    Buffer buffer = buffer_list.nth_data (buffer_notebook.get_current_page ());
    if (check_firmware_signature (firmware_name) == false)
      if (load_firmware (firmware_name, false) == false)
        return;
    mem_action.verify_data.begin (buffer.get_in_stream (), (obj, res) => {
        mem_action.verify_data.end (res);
    });
  }

  private void action_write () {
    Buffer buffer = buffer_list.nth_data (buffer_notebook.get_current_page ());
    if (check_firmware_signature (firmware_name) == false)
      if (load_firmware (firmware_name, false) == false)
        return;
    mem_action.write_data.begin (buffer.get_in_stream (), (obj, res) => {
        mem_action.write_data.end (res);
    });
  }

  private void action_erase () {
    var msg = new Gtk.MessageDialog (window, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO,
                                     "Do you really want to erase all memory data?");
    int response = msg.run ();
    msg.destroy ();
    if (response == Gtk.ResponseType.YES) {
      mem_action.erase_chip.begin ( (obj, res) => {
          mem_action.erase_chip.end (res);
      });
    }
  }

  private void action_blank () {
    mem_action.blank_check.begin ( (obj, res) => {
        mem_action.blank_check.end (res);
    });
  }

  private void action_settings () {
    
  }
  
  private void on_device_activated (Gtk.TreePath path, Gtk.TreeViewColumn column) {
    DeviceTreeDepth depth = (DeviceTreeDepth) path.get_depth ();
    
    if (depth != DeviceTreeDepth.VARIANT)
      return;
    
    if (!close_all_buffers ())
      return;
    
    Value id;
    Gtk.TreeModel model = device_treeview.get_model ();
    Gtk.TreeIter iter;
    model.get_iter (out iter, path);
    model.get_value (iter, DeviceTreeColumn.ID, out id);
    
    try {
      mem_device = new MemoryDevice(db_manager, (int) id);
    } catch (DBError e) {
      new ErrorMessage (window, "Can't create device object (VariantId: %d)".printf ((int) id),
                        "DB Error: %s".printf (e.message));
      mem_device = null;
    }
    
    try {
      description_box.update (mem_device);
      if (mem_device != null) {
        firmware_name = mem_device.get_interface_name ();
        mem_config = new MemoryDeviceConfig (mem_device, nvmemprog);
      }
    } catch (DBError e) {
      new ErrorMessage (window, "Can't obtain device information (VariantId: %d)".printf ((int) mem_device.variant_id),
                        "DB Error: %s".printf (e.message));
    }
    update_memory_actions ();
    update_buffer_actions ();
    if (mem_device != null) {
      mem_action = new MemoryAction (mem_device, mem_config, nvmemprog, window);
      (window.get_action_group ("buffer") as SimpleActionGroup).activate_action ("new", null);
    }
  }
  
  
  private bool load_firmware (string name, bool first_load) {
    try {
      status_cancellable.cancel ();
      nvmemprog.load_firmware ("%s/%s.ihx".printf (FIRMWARE_DIRECTORY, name));
      statusbar.pop (statusbar_status_id);
      statusbar.push (statusbar_status_id, "Firmware loaded successfully");
      if (first_load == false) {
        signature_label.set_label ("[%s]".printf (nvmemprog.get_firmware_signature ()));
        begin_status_polling ();
      }
      return true;
    } catch (Error e) {
      if (e is UsbError)
        critical ("USB Error: " + e.message + "\n");
      else
        critical ("Error: " + e.message + "\n");
      statusbar.pop (statusbar_status_id);
      statusbar.push (statusbar_status_id, "Error during firmware load");
      signature_label.set_label ("");
      return false;
    }
  }
  
  private bool check_firmware_signature (string? name) {
    try {
      string signature = nvmemprog.get_firmware_signature ();
      return name == null ? true : signature == name;
    } catch (UsbError e) {
      return false;
    }
  }
  
  private void begin_status_polling () {
    status_cancellable = new Cancellable ();
    nvmemprog.poll_status.begin (status_cancellable, (obj, res) => {
      try {
        nvmemprog.poll_status.end (res);
      } catch (UsbError e) {
        if (!(e is UsbError.DISCONNECTED)) {
          critical ("USB Error: " + e.message + "\n");
          usb.disconnect ();
          update_memory_actions ();
          statusbar.pop (statusbar_status_id);
          statusbar.push (statusbar_status_id, "Error during status poll");
        }
      } catch (IOError e) { }
    });
  }
  
  private bool on_nvmemprog_connected_timeout () {
    if (check_firmware_signature (null)) {
      try {
        signature_label.set_label ("[%s]".printf (nvmemprog.get_firmware_signature ()));
        begin_status_polling ();
      } catch (UsbError e) {
        critical ("Error: " + e.message + "\n");
        usb.disconnect ();
      }
      update_memory_actions ();
      loading_fw_after_connect = false;
    } else {  // nvmemprog is not initialized (has no firmware loaded)
      load_firmware (firmware_name, true);
      loading_fw_after_connect = true;
    }
    connect_timeout_id = 0;
    return false;
  }

  private void on_nvmemprog_connected () {
    statusbar.pop (statusbar_status_id);
    statusbar.push (statusbar_status_id, "NVMemProg connected");
    connection_label.set_label ("<span foreground='green'>Connected</span>");
    connect_timeout_id = Timeout.add (800, on_nvmemprog_connected_timeout);
  }
  
  private void on_nvmemprog_disconnected () {
    if (connect_timeout_id != 0) {
      Source.remove (connect_timeout_id);
      connect_timeout_id = 0;
    }
    if (!loading_fw_after_connect) {
      statusbar.pop (statusbar_status_id);
      statusbar.push (statusbar_status_id, "NVMemProg disconnected");
    }
    connection_label.set_label ("<span foreground='red'>Disconnected</span>");
    signature_label.set_label ("");
    update_memory_actions ();
  }
  
  private void on_nvmemprog_button () {
    var msg = new Gtk.MessageDialog (window, Gtk.DialogFlags.MODAL, Gtk.MessageType.INFO, Gtk.ButtonsType.OK, "Button");
    msg.run ();
    msg.destroy ();
  }
    
  
  protected override void activate () {
    // UI Layout
    window = new Gtk.ApplicationWindow (this);
    window.title = "NVMemProg";
    window.window_position = Gtk.WindowPosition.CENTER;
		window.set_default_size (710, 480);
    
    // Database
    try {
      db_manager = new DBManager(DATABASE_FILENAME);
    } catch (DBError e) {
      new ErrorMessage (window, "Can't open database: " + e.message);
      this.quit ();
      return;
    }
    
    // Usb interface
    if (Thread.supported () == false) {
      new ErrorMessage (window, "Can't run without thread support");
      this.quit ();
      return;
    }
    try {
      usb = new UsbInterface ();
    } catch (UsbError e) {
      new ErrorMessage (window, "Can't initialize usb interface", "USB Error: %s\n".printf(e.message));
      this.quit ();
      return;
    }
    
    
    setup_actions (window);
    
    var hpaned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
    var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
    hpaned.set_size_request (640, 480);
    
    // Device List
    var device_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
    device_filter_entry = new Gtk.SearchEntry ();
    var device_scrolled = new Gtk.ScrolledWindow (null, null);
    device_treeview = new Gtk.TreeView ();
    var device_edit_hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
    
      device_vbox.pack_start (device_filter_entry, false);
          setup_device_treeview ();
          device_treeview.cursor_changed.connect (update_device_edit_actions);
          device_treeview.row_activated.connect (on_device_activated);
        device_scrolled.add (device_treeview);
      device_vbox.pack_start (device_scrolled, true, true);
        setup_device_edit_buttons (device_edit_hbox);
      device_vbox.pack_start (device_edit_hbox, false);
    hpaned.pack1 (device_vbox, true, false);
    update_device_edit_actions ();
    
    // Device List expander
    var device_expander = new Gtk.Expander ("");
    var device_expander_label = new Gtk.Label ("Device List");
    var device_expander_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
    
        device_expander.activate.connect (() => {
          if (device_expander.get_expanded ())
            device_vbox.show ();
          else
            device_vbox.hide ();
          hpaned.check_resize ();
        });
      device_expander_vbox.pack_start (device_expander, false);
        device_expander_label.set_angle (90);
      device_expander_vbox.pack_start (device_expander_label, false);
    hbox.pack_start (device_expander_vbox, false);
    
    
    // Main Frame
    var main_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
    var description_scrolled = new Gtk.ScrolledWindow (null, null);
    description_box = new DescriptionBox ();
    var main_hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
    var buffer_frame = new Gtk.Frame ("<i><b>Buffer</b></i>");
    var buffer_vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
    var buffer_toolbar = new Gtk.Toolbar ();
    buffer_notebook = new Gtk.Notebook ();
  
    var actions_frame = new Gtk.Frame ("<i><b>Action</b></i>");
    var action_bbox = new Gtk.ButtonBox (Gtk.Orientation.VERTICAL);
    connection_label = new Gtk.Label ("<span foreground='red'>Disconnected</span>");
    signature_label = new Gtk.Label ("");
    statusbar = new Gtk.Statusbar ();
    
        description_scrolled.add (description_box);
        description_scrolled.set_size_request (-1, 69);
      main_vbox.pack_start (description_scrolled, false);
              buffer_toolbar = new Gtk.Toolbar ();
              setup_buffer_toolbuttons (buffer_toolbar);
              buffer_toolbar.set_size_request (250, -1);
            buffer_vbox.pack_start (buffer_toolbar, false);
              buffer_notebook.set_show_border (false);
              buffer_notebook.set_scrollable (true);
              buffer_notebook.switch_page.connect ( () => {
                  update_buffer_actions ();
                });
            buffer_vbox.pack_start (buffer_notebook, true, true);
          buffer_frame.add (buffer_vbox);
          (buffer_frame.label_widget as Gtk.Label).use_markup = true;
        main_hbox.pack_start (buffer_frame, true, true);
            setup_memory_action_buttons (action_bbox);
          actions_frame.add (action_bbox);
          (actions_frame.label_widget as Gtk.Label).use_markup = true;
        main_hbox.pack_start (actions_frame, false);
        main_hbox.set_margin_left (3); main_hbox.set_margin_right (3);
      main_vbox.pack_start (main_hbox, true, true);
        connection_label.set_use_markup (true);
        statusbar.pack_end (connection_label, false);
        statusbar.pack_end (signature_label, false);
      statusbar_status_id = statusbar.get_context_id ("status");
      main_vbox.pack_start (statusbar, false);
    hpaned.pack2 (main_vbox, true, false);
    hbox.pack_start (hpaned);
    update_buffer_actions ();
    update_memory_actions ();
    
    window.add (hbox);
    window.show_all ();
    
    // USB Interface
    loading_fw_after_connect = false;
    nvmemprog = new NVMemProgDevice (usb);
    usb.device_connected.connect (on_nvmemprog_connected);
    usb.device_disconnected.connect (on_nvmemprog_disconnected);
    nvmemprog.button_pressed.connect (on_nvmemprog_button);
    try {
      usb.register_hotplug ();
    } catch (UsbError e) {
      new ErrorMessage (window, "Can't register hotplug callback", "USB Error: %s\n".printf(e.message));
      this.quit ();
      return;
    }
    try{
      usb.run_thread ();
    } catch (Error e) {
      new ErrorMessage (window, "Can't run usb interface thread", "Error: %s\n".printf(e.message));
      this.quit ();
      return;
    }
  }
  
  
  protected override int handle_local_options (VariantDict options) {
    if (version) {
      stdout.printf ("NVMemProg application v0.1\n");
      return 0;
    }
    
    return -1;
  }
  
  
  public static int main(string[] args) {
    var app = new NVMemProgApplication();
    
    app.add_main_option_entries (options);
    
    return app.run (args);
  }
}
