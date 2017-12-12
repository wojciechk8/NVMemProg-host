[CCode (cheader_filename = "hex-document.h", type_id = "hex_document_get_type ()", cprefix = "hex_document_", unref_function = "")]
public class HexDocument : GLib.Object {
  [CCode (has_construct_function = false)]
  public HexDocument ();
  [CCode (has_construct_function = false)]
  public HexDocument.from_file (string name);
  public void set_data (uint offset, uint rep_len, [CCode (array_length_pos = 1.1)] uint8[] data, bool undoable);
  public void set_byte (uint8 val, uint offset, bool insert, bool undoable);
  public void set_nibble (uint8 val, uint offset, bool lower_nibble, bool insert, bool undoable);
  public uint8 get_byte (uint offset);
  [CCode (cname = "hex_document_get_data", array_length = false)]
  private uint8[] _get_data (uint offset, uint len);
  [CCode (cname = "vala_get_data")]
  public uint8[] get_data (uint offset, uint len) {
    uint8[] temp;
    temp = _get_data (offset, len);
    temp.length = (int) len;
    return temp;
  }
  public void delete_data (uint offset, uint len, bool undoable);
  public bool read ();
  public bool write ();
  public bool write_to_file (Posix.FILE file);
  public bool export_html(string html_path, string base_name, uint start, uint end, uint cpl, uint lpp, uint cpw);
  public bool has_changed();
  public void changed(void* change_data, bool push_undo);
  public void set_max_undo(uint max_undo);
  public bool undo ();
  public bool redo ();
  public int compare_data([CCode (array_length_pos = 2.1)]  uint8[] s2, int pos);
  public int find_forward(uint start, uint8[] what, ref uint found);
  public int find_backward(uint start, uint8[] what, ref uint found);
  public void remove_view(Gtk.Widget view);
  public Gtk.Widget add_view();
  public unowned GLib.List<weak HexDocument> get_list();
  public bool is_writable();
  
  public virtual signal void document_changed (void* change_data, bool push_undo);
}

[CCode (cheader_filename = "gtkhex.h", type_id = "gtk_hex_get_type ()", cprefix = "gtk_hex_")]
public class GtkHex : Gtk.Widget {
  [CCode (cname = "GROUP_BYTE")]
  public const uint GROUP_BYTE;
  [CCode (cname = "GROUP_WORD")]
  public const uint GROUP_WORD;
  [CCode (cname = "GROUP_LONG")]
  public const uint GROUP_DWORD;

  [CCode (cname = "LOWER_NIBBLE")]
  public const bool LOWER_NIBBLE;
  [CCode (cname = "UPPER_NIBBLE")]
  public const bool UPPER_NIBBLE;

  [CCode (has_construct_function = false, type = "GtkWidget*")]
  public GtkHex (HexDocument doc);
  public void set_cursor (int index);
  public void set_cursor_xy (int x, int y);
  public void set_nibble (int lower_nibble);
  public uint get_cursor ();
  public uint8 get_byte (uint pos);
  public void set_group_type (uint gt);
  public void set_starting_offset (int offset);
  public void show_offsets (bool show);
  public void set_font (Pango.FontMetrics font_metrics, Pango.FontDescription font_desc);
  public void set_insert_mode (bool insert);
  public void set_geometry (int cpl, int vis_lines);
  public static Pango.FontMetrics load_font (string font_name); 
  public void copy_to_clipboard ();
  public void cut_to_clipboard ();
  public void paste_from_clipboard ();

  //void add_atk_namedesc(GtkWidget *widget, const gchar *name, const gchar *desc);
  //void add_atk_relation(GtkWidget *obj1, GtkWidget *obj2, AtkRelationType type);

  public void set_selection(int start, int end);
  public bool get_selection(out int start, out int end);
  public void clear_selection();
  public void delete_selection();

  //GtkHex_AutoHighlight *gtk_hex_insert_autohighlight(GtkHex *gh, const gchar *search, gint len, const gchar *colour);
  //void gtk_hex_delete_autohighlight(GtkHex *gh, GtkHex_AutoHighlight *ahl);
}

