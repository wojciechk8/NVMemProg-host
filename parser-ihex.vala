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


public errordomain ParserError {
  INVALID_FORMAT,
  INVALID_TYPE,
  INVALID_CHECKSUM
}


public class IHexParser {
  private uint line;
  
  //[Compact]
  public class Record {
    public uint8 byte_cnt;
    public uint16 addr;
    [CCode (type_id = "G_TYPE_UINT8")]
    public enum Type {
      DATA = 0,
      EOF = 1,
      EXT_SEGMENT_ADDR = 2,
      START_SEGMENT_ADDR = 3,
      EXT_LINEAR_ADDR = 4,
      START_LINEAR_ADDR = 5
    }
    public Type type;
    public uint8[] data;
  }
  
  public GenericSet<Record?> records;
  
  
  private Record parse_record (string record_str) throws ParserError {
    Record record = new Record ();
    uint8 checksum_calc, checksum_read = 0;
    
    if (record_str.get (0) != ':') {
      throw new ParserError.INVALID_FORMAT ("Line %u: Missing start character (:)".printf (line));
    }
    record_str = record_str.offset (1);
    
    if (record_str.scanf ("%02hhx%04hx%02hhx", &record.byte_cnt, &record.addr, &record.type) != 3) {
      throw new ParserError.INVALID_FORMAT ("Line %u: Wrong header in record_str".printf (line));
    }
    record_str = record_str.offset (8);
    checksum_calc = record.byte_cnt + (uint8) (record.addr >> 8) + (uint8) record.addr + record.type;
    record.data = new uint8[record.byte_cnt];
    
    switch (record.type) {
      case Record.Type.DATA:
        for (uint i = 0; i < record.byte_cnt; i++) {
          uint8 byte = 0;
          if (record_str.scanf ("%02hhx", &byte) != 1) {
            throw new ParserError.INVALID_FORMAT ("Line %u: Wrong data in record_str".printf (line));
          }
          record_str = record_str.offset (2);
          record.data[i] = byte;
          checksum_calc += byte;
        }
        break;
      
      case Record.Type.EOF:
        break;
      
      default:
        throw new ParserError.INVALID_TYPE ("Line %u: Wrong record_str type (%u)".printf (line, record.type));
    }
    
    checksum_calc = -(checksum_calc & 0xFF);
    if (record_str.scanf ("%02hhx", &checksum_read) != 1) {
      throw new ParserError.INVALID_FORMAT ("Line %u: Wrong checksum format".printf (line));
    }
    if (checksum_calc != checksum_read) {
      throw new ParserError.INVALID_CHECKSUM ("Line %u: Wrong checksum (was %02X, should be %02X)".printf (line, checksum_read, checksum_calc));
    }
    return record;
  }
  
  public void parse_file (string filename) throws Error, ParserError {
    File file = File.new_for_path (filename);
    if (file.query_exists () == false) {
      throw new FileError.NOENT ("File %s not found".printf (filename));
    }
    line = 1;
    
    var stream = new DataInputStream (file.read ());
    records = new GenericSet<Record> (null, null);
    bool eof = false;
    
    for (;; line++) {
      string record_str = stream.read_line ();
      if (record_str != null) {
        Record record;
        record = parse_record ((string) record_str);
        records.add (record);
        if (record.type == Record.Type.EOF) {
          eof = true;
          break;
        }
      } else {
        break;
      }
    }
    if (eof == false) {
      throw new ParserError.INVALID_FORMAT ("Missing End Of File record_str");
    }
  }
}
