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


public enum MemoryDeviceType {
  EEPROM = 1,
  EPROM = 2,
  SPI_FLASH = 3,
  I2C_EEPROM = 4,
  AVR = 5
}


public errordomain DBError {
  ERROR,
  CANTOPEN
}


public class DBManager {
  private Sqlite.Database db;
  private Sqlite.Statement stmt;


  private Variant? variant_from_sqlite_field (int column) {
    switch (stmt.column_type (column)) {
      case Sqlite.INTEGER:
        return new Variant.int64 (stmt.column_int64 (column));
      case Sqlite.FLOAT:
        return new Variant.double (stmt.column_double (column));
      case Sqlite.BLOB:
        uint8[] tmp = new uint8[stmt.column_bytes (column)];
        Memory.copy (tmp, stmt.column_blob (column), stmt.column_bytes (column));
        return Variant.new_fixed_array<uint8> (VariantType.BYTE, tmp, 1);
      case Sqlite.TEXT:
        return new Variant.string (stmt.column_text (column));
      case Sqlite.NULL:
        return null;
      default:
        assert_not_reached ();
    }
  }
  
  
  public DBManager (string filename) throws DBError {
    int ec;
    ec = Sqlite.Database.open_v2 (filename, out db, Sqlite.OPEN_READWRITE);
    if (ec == Sqlite.CANTOPEN) {
      throw new DBError.CANTOPEN (db.errmsg ());
    } else if (ec != Sqlite.OK) {
      throw new DBError.ERROR (db.errmsg ());
    }
  }
  
  
  public Variant? query_value (string table, string field, int id) throws DBError {
    string query = @"SELECT $field FROM $table WHERE Id = ?1;";
    stmt = null;
    if (db.prepare_v2 (query, query.length, out stmt) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (stmt.bind_int (1, id) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (stmt.step () == Sqlite.ROW)
      return variant_from_sqlite_field (0);
    else
      return null;
  }
  
  public void query_related_values (string relvar, string attribute, string table, string key, int id, string? order = null) throws DBError {
    string query =
      @"SELECT $relvar.$attribute FROM $relvar
        JOIN $table ON $table.$key = $relvar.Id
        WHERE $table.Id = ?1"
      + (order != null ? @" ORDER BY $order;" : ";");
    stmt = null;
    if (db.prepare_v2 (query, query.length, out stmt) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (stmt.bind_int (1, id) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
  }
  
  public Variant? query_related_value (string relvar, string attribute, string table, string key, int id) throws DBError {
    query_related_values (relvar, attribute, table, key, id);
    if (next_row ())
      return get_current_row () [0];
    else
      return null;
  }
  
  
  public void query_pin_numbers (int device_variant_id, string pin_name, bool bus, int bus_index) throws DBError {
    string query =
      @"SELECT DevicePinouts.SocketPin FROM DevicePinouts
        JOIN DeviceVariants ON DeviceVariants.PackageVariantId = DevicePackageVariants.Id
        JOIN DevicePackageVariants ON DevicePackageVariants.PinoutId = DevicePinouts.Id
        JOIN DevicePinFunctions ON DevicePinFunctions.Id = DevicePinouts.FunctionId
        WHERE DeviceVariants.Id = ?1 AND DevicePinFunctions.Name = ?2"
      + (bus ? " AND DevicePinouts.BusIndex = ?3;" : ";");
    stmt = null;
    if (db.prepare_v2 (query, query.length, out stmt) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (stmt.bind_int (1, device_variant_id) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (stmt.bind_text (2, pin_name) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (bus) {
      if (stmt.bind_int (3, bus_index) != Sqlite.OK)
        throw new DBError.ERROR (db.errmsg ());
    }
  }
  
  public Variant? query_pin_number (int device_variant_id, string pin_name, bool bus, int bus_index) throws DBError {
    query_pin_numbers (device_variant_id, pin_name, bus, bus_index);
    if (next_row ())
      return get_current_row () [0];
    else
      return null;
  }
  
  
  public void query_table (string table, string[] fields, string? order = null) throws DBError {
    string query = @"SELECT $(fields[0])";
    for (int i = 1; i < fields.length; i++) {
      query += @", $(fields[i])";
    }
    query += @" FROM $table";
    if (order != null)
      query += @" ORDER BY $order;";
    stmt = null;
    if (db.prepare_v2 (query, query.length, out stmt) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
  }
  
  public void query_table_filtered_by_id (string table, string[] fields, string id_field, int id, string? order = null) throws DBError {
    string query = @"SELECT $(fields[0])";
    for (int i = 1; i < fields.length; i++) {
      query += @", $(fields[i])";
    }
    query += @" FROM $table WHERE $id_field = ?1";
    if (order != null)
      query += @" ORDER BY $order;";
    stmt = null;
    if (db.prepare_v2 (query, query.length, out stmt) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
    if (stmt.bind_int (1, id) != Sqlite.OK)
      throw new DBError.ERROR (db.errmsg ());
  }

  public Variant?[] get_current_row () {
    Variant?[] row = new Variant[stmt.column_count ()];
    for (int i = 0; i < stmt.column_count (); i++) {
      row[i] = variant_from_sqlite_field (i);
    }
    return row;
  }
  
  public bool next_row () {
    if (stmt.step () == Sqlite.ROW)
      return true;
    else
      return false;
  }
}
