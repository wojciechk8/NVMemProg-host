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


public class MemoryDeviceList {
  private DBManager db_manager;
  
  public MemoryDeviceList (DBManager db_manager) {
    this.db_manager = db_manager;
  }
  
  public HashTable<int, string> get_device_types () throws DBError {
    var table = new HashTable<int, string> (direct_hash, direct_equal);
    db_manager.query_table ("DeviceTypes", {"Id", "Name"}, "Id");
    while (db_manager.next_row ()) {
      Variant[] row = db_manager.get_current_row ();
      table.insert ((int) row[0].get_int64 (), row[1].get_string ());
    }
    return table;
  }
  
  public HashTable<int, string> get_devices (int type_id) throws DBError {
    var table = new HashTable<int, string> (direct_hash, direct_equal);
    db_manager.query_table_filtered_by_id ("Devices", {"Id", "Name"}, "DeviceTypeId", type_id, "Name");
    while (db_manager.next_row ()) {
      Variant[] row = db_manager.get_current_row ();
      table.insert ((int) row[0].get_int64 (), row[1].get_string ());
    }
    foreach (int id in table.get_keys ()) {
      string manufacturer = db_manager.query_related_value ("Manufacturers", "Name", "Devices", "ManufacturerId", id).get_string ();
      table.set (id, "%s [%s]".printf(table.get (id), manufacturer));
    }
    return table;
  }
  
  public HashTable<int, string> get_device_variants (int device_id) throws DBError {
    var table = new HashTable<int, string> (direct_hash, direct_equal);
    db_manager.query_table_filtered_by_id ("DeviceVariants", {"Id", "Name"}, "DeviceId", device_id, "Name");
    while (db_manager.next_row ()) {
      Variant[] row = db_manager.get_current_row ();
      table.insert ((int) row[0].get_int64 (), row[1].get_string ());
    }
    foreach (int id in table.get_keys ()) {
      int package_variant_id = (int) db_manager.query_related_value ("DevicePackageVariants", "PackageId", "DeviceVariants", "PackageVariantId", id).get_int64 ();
      string package = db_manager.query_related_value ("Packages", "Name", "DevicePackageVariants", "PackageId", package_variant_id).get_string ();
      package += db_manager.query_related_value ("DevicePackageVariants", "PinCount", "DeviceVariants", "PackageVariantId", id).get_int64 ().to_string ();
      table.set (id, "%s [%s]".printf(table.get (id), package));
    }
    return table;
  }
}


public class MemoryDevice {
  private DBManager db_manager;
  public int device_id { get; private set; }
  public int variant_id { get; private set; }
  
  public MemoryDevice (DBManager db_manager, int variant_id) throws DBError {
    this.db_manager = db_manager;
    this.variant_id = variant_id;
    this.device_id = (int) db_manager.query_related_value ("Devices", "Id", "DeviceVariants", "DeviceId", variant_id).get_int64 ();
  }
  
  
  public string get_dev_type () throws DBError { return db_manager.query_related_value ("DeviceTypes", "Name", "Devices", "DeviceTypeId", device_id).get_string (); }
  public string get_name () throws DBError { return db_manager.query_value ("DeviceVariants", "Name", variant_id).get_string (); }
  public string get_manufacturer () throws DBError { return db_manager.query_related_value ("Manufacturers", "Name", "Devices", "ManufacturerId", device_id).get_string (); }
  public string get_package () throws DBError { int package_variant_id = (int) db_manager.query_related_value ("DevicePackageVariants", "PackageId", "DeviceVariants", "PackageVariantId", variant_id).get_int64 ();
                                                return db_manager.query_related_value ("Packages", "Name", "DevicePackageVariants", "PackageId", package_variant_id).get_string (); }
  public int get_pin_count () throws DBError { return (int) db_manager.query_related_value ("DevicePackageVariants", "PinCount", "DeviceVariants", "PackageVariantId", variant_id).get_int64 (); }
  public int get_speed () throws DBError { return (int) db_manager.query_related_value ("DeviceSpeedVariants", "AccessTime", "DeviceVariants", "SpeedVariantId", variant_id).get_int64 (); }
  public int[] get_pin_numbers (string pin_name, bool bus = false, int bus_index = 0) throws DBError {
    int[] result = {};
    db_manager.query_pin_numbers (variant_id, pin_name, bus, bus_index);
    while (db_manager.next_row ())
      result += (int) db_manager.get_current_row () [0].get_int64 ();
    return result;
  }
  public uint64 get_size () throws DBError { return (uint64) db_manager.query_value ("Devices", "Size", device_id).get_int64 (); }
  public bool has_block_structure () throws DBError { return db_manager.query_value ("Devices", "BlockStructureId", device_id) != null; }
  public uint[] get_block_sizes () throws DBError { uint[] result = {};
                                                    db_manager.query_related_values ("BlockStructures", "BlockSize", "Devices", "BlockStructureId", device_id, "BlockStructures.BlockNumber");
                                                    while (db_manager.next_row ())
                                                      result += (uint) db_manager.get_current_row () [0].get_int64 ();
                                                    return result; }
  public string get_interface_name () throws DBError { return db_manager.query_related_value ("InterfaceModules", "Name", "Devices", "InterfaceModuleId", device_id).get_string (); }
  public string get_fpga_module_name () throws DBError { int ifc_id = (int) db_manager.query_value ("Devices", "InterfaceModuleId", device_id).get_int64 ();
                                                         return db_manager.query_related_value ("FpgaModules", "Name", "InterfaceModules", "FpgaModuleId", ifc_id).get_string (); }
  public uint8[]? get_fpga_module_rbf_data () throws DBError { int ifc_id = (int) db_manager.query_value ("Devices", "InterfaceModuleId", device_id).get_int64 ();
                                                               Variant? val = db_manager.query_related_value ("FpgaModules", "RBF", "InterfaceModules", "FpgaModuleId", ifc_id);
                                                               if (val == null) return null;
                                                               else return val.get_data_as_bytes ().get_data (); }
  public uint8[]? get_manufacturer_code () throws DBError { Variant? val = db_manager.query_related_value ("IdentificationCodes", "ManufacturerCode", "Devices", "IdentificationCodeId", device_id);
                                                            if (val == null) return null;
                                                            else return val.get_data_as_bytes ().get_data (); }
  public uint8[]? get_device_code () throws DBError { Variant? val = db_manager.query_related_value ("IdentificationCodes", "DeviceCode", "Devices", "IdentificationCodeId", device_id);
                                                      if (val == null) return null;
                                                      else return val.get_data_as_bytes ().get_data (); }
  public uint8[]? get_extended_code () throws DBError { Variant? val = db_manager.query_related_value ("IdentificationCodes", "ExtendedCode", "Devices", "IdentificationCodeId", device_id);
                                                        if (val == null) return null;
                                                        else return val.get_data_as_bytes ().get_data (); }
  public float get_vcc () throws DBError { return (float) db_manager.query_value ("Devices", "Vcc", device_id).get_double (); }
  public float get_vcc_prog () throws DBError { Variant? val = db_manager.query_value ("Devices", "VccProg", device_id);
                                                if (val == null) return 0;
                                                else return (float) val.get_double (); }
  public float get_vpp () throws DBError { Variant? val = db_manager.query_value ("Devices", "Vpp", device_id);
                                           if (val == null) return 0;
                                           else return (float) val.get_double (); }
  public float get_vid () throws DBError { Variant? val = db_manager.query_value ("Devices", "Vid", device_id);
                                           if (val == null) return 0;
                                           else return (float) val.get_double (); }
  public int get_icc () throws DBError { return (int) db_manager.query_value ("Devices", "Icc", device_id).get_int64 (); }
  public int get_ipp () throws DBError { Variant? val = db_manager.query_value ("Devices", "Ipp", device_id);
                                         if (val == null) return 0;
                                         else return (int) val.get_int64 (); }
  public int get_chip_erase_time () throws DBError { Variant? val = db_manager.query_value ("Devices", "ChipEraseTime", device_id);
                                                     if (val == null) return 0;
                                                     else return (int) val.get_int64 (); }
  public bool get_has_read_id_capability () throws DBError { return db_manager.query_related_value ("DeviceCapabilities", "ReadId", "Devices", "DeviceCapabilitiesId", device_id).get_int64 () != 0; }
  public bool get_has_read_capability () throws DBError { return db_manager.query_related_value ("DeviceCapabilities", "Read", "Devices", "DeviceCapabilitiesId", device_id).get_int64 () != 0; }
  public bool get_has_write_capability () throws DBError { return db_manager.query_related_value ("DeviceCapabilities", "Write", "Devices", "DeviceCapabilitiesId", device_id).get_int64 () != 0; }
  public bool get_has_erase_capability () throws DBError { return db_manager.query_related_value ("DeviceCapabilities", "Erase", "Devices", "DeviceCapabilitiesId", device_id).get_int64 () != 0; }
  public bool get_has_cfi_capability () throws DBError { return db_manager.query_related_value ("DeviceCapabilities", "CFI", "Devices", "DeviceCapabilitiesId", device_id).get_int64 () != 0; }
  public bool get_has_onfi_capability () throws DBError { return db_manager.query_related_value ("DeviceCapabilities", "ONFi", "Devices", "DeviceCapabilitiesId", device_id).get_int64 () != 0; }
}


public class MemoryDeviceConfig {
  MemoryDevice device;
  NVMemProgDevice nvmemprog;
  
  HashTable<string, int> ctl_pin_map;
  
  const int ADDRESS_BUS_WIDTH_FX = 9;
  const int ADDRESS_BUS_WIDTH_MAX = 9+16;
  const int DATA_BUS_WIDTH_MAX = 16;
  
  public delegate void FpgaRegisterConfig () throws DBError, UsbError;
  public delegate void InterfaceConfig () throws DBError, UsbError;
  
  public FpgaRegisterConfig configure_fpga_registers;
  public InterfaceConfig configure_interface;
  
  const float DEFAULT_VCC_RATE = 0.5f;
  const float DEFAULT_VPP_RATE = 0.25f;
  public float vcc { get; private set; }
  public float vcc_prog { get; private set; }
  public float vcc_rate { get; private set; }
  public float vpp { get; private set; }
  public float vid { get; private set; }
  public float vpp_rate { get; private set; }
  public uint icc { get; private set; }
  public uint ipp { get; private set; }
  
  
  public MemoryDeviceConfig (MemoryDevice device, NVMemProgDevice nvmemprog) throws DBError {
    this.device = device;
    this.nvmemprog = nvmemprog;
    
    ctl_pin_map = new HashTable<string, int> (str_hash, str_equal);
    // TODO: make this mapping configurable in the UI or in the database
    ctl_pin_map.insert ("CE#", 0);
    ctl_pin_map.insert ("WE#", 1);
    ctl_pin_map.insert ("PGM#", 1);
    ctl_pin_map.insert ("OE#", 2);
    ctl_pin_map.insert ("OE#/Vpp", 2);
    
    vcc = device.get_vcc ();
    vcc_prog = device.get_vcc_prog ();
    vcc_rate = DEFAULT_VCC_RATE;
    vpp = device.get_vpp ();
    vid = device.get_vid ();
    vpp_rate = DEFAULT_VPP_RATE;
    icc = device.get_icc ();
    ipp = device.get_ipp ();
    
    switch (device.get_fpga_module_name ()) {
      case "Universal":
        configure_fpga_registers = configure_fpga_registers_universal;
        break;
      case "SPI":
        configure_fpga_registers = configure_fpga_registers_spi;
        break;
      default:
        assert_not_reached ();
    }
    
    switch (device.get_interface_name ()) {
      case "mx28f":
        configure_interface = configure_interface_mx28f;
        break;
      case "27c512":
        configure_interface = configure_interface_27c512;
        break;
      case "28f":
        configure_interface = configure_interface_28f;
        break;
      case "am27":
        configure_interface = configure_interface_am27;
        break;
      case "29c":
        configure_interface = configure_interface_29c;
        break;
      default:
        assert_not_reached ();
    }
  }
  
  
  public void configure_driver (MemoryAction.Type action) throws DBError, UsbError {
    NVMemProg.DriverConfig _config = NVMemProg.DriverConfig ();
    NVMemProg.DriverConfig *config = &_config;
    
    // unused pins
    for (int i = 0; i < config.pin_config.length; i++)
      config.pin_config[i] = NVMemProg.DriverPinConfig.IO | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
    // GND
    foreach (int pin_num in device.get_pin_numbers ("GND")) 
      config.pin_config[pin_num-1] = NVMemProg.DriverPinConfig.GND | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
    // Vcc
    foreach (int pin_num in device.get_pin_numbers ("Vcc")) 
      config.pin_config[pin_num-1] = NVMemProg.DriverPinConfig.VCC | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
    // Vpp/Vid
    foreach (int pin_num in device.get_pin_numbers ("Vpp")){
      if (action == MemoryAction.Type.WRITE)
        config.pin_config[pin_num-1] = NVMemProg.DriverPinConfig.VPP | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
      else
        config.pin_config[pin_num-1] = NVMemProg.DriverPinConfig.VCC | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
    }
    foreach (int pin_num in device.get_pin_numbers ("OE#/Vpp")){
      if (action == MemoryAction.Type.WRITE)
        config.pin_config[pin_num-1] = NVMemProg.DriverPinConfig.VPP | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
    }
    foreach (int pin_num in device.get_pin_numbers ("A9/Vid")){
      if (action == MemoryAction.Type.READ_ID)
        config.pin_config[pin_num-1] = NVMemProg.DriverPinConfig.VPP | NVMemProg.DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
    }
    
    nvmemprog.configure_driver ((uint8[]) config);
  }
  
  
  // FPGA registers config functions
  private void configure_fpga_registers_universal () throws DBError, UsbError {
    NVMemProg.FpgaUnivRegisters _regs = NVMemProg.FpgaUnivRegisters ();
    NVMemProg.FpgaUnivRegisters* regs = &_regs;
    
    // unused pins
    for (int i = 0; i < regs.mem_mux_selector.length; i++) {
      regs.mem_mux_selector[i] = NVMemProg.FpgaUnivMuxSelector.LOW;  // Hi-Z
    }
    // address bus
    for (int i = 0; i < ADDRESS_BUS_WIDTH_FX; i++) {
      foreach (int pin_num in device.get_pin_numbers ("AddressBus", true, i))
        regs.mem_mux_selector[pin_num-1] = NVMemProg.FPGA_UNIV_MUX_ENABLE | (NVMemProg.FpgaUnivMuxSelector.ADDR_FX + i);
    }
    for (int i = ADDRESS_BUS_WIDTH_FX; i < ADDRESS_BUS_WIDTH_MAX; i++) {
      foreach (int pin_num in device.get_pin_numbers ("AddressBus", true, i))
        regs.mem_mux_selector[pin_num-1] = NVMemProg.FPGA_UNIV_MUX_ENABLE | NVMemProg.FpgaUnivMuxSelector.LOW;
    }
    foreach (int pin_num in device.get_pin_numbers ("A9/Vid"))
      regs.mem_mux_selector[pin_num-1] = NVMemProg.FPGA_UNIV_MUX_ENABLE | NVMemProg.FpgaUnivMuxSelector.LOW;
    // data bus
    for (int i = 0; i < DATA_BUS_WIDTH_MAX; i++) {
      foreach (int pin_num in device.get_pin_numbers ("DataBus", true, i))
        regs.mem_mux_selector[pin_num-1] = NVMemProg.FPGA_UNIV_MUX_ENABLE | (NVMemProg.FpgaUnivMuxSelector.DATA_FX + i);
    }
    // control
    foreach (string ctl_pin in ctl_pin_map.get_keys ()) {
      foreach (int pin_num in device.get_pin_numbers (ctl_pin))
        regs.mem_mux_selector[pin_num-1] = NVMemProg.FPGA_UNIV_MUX_ENABLE | (NVMemProg.FpgaUnivMuxSelector.CTL_FX + ctl_pin_map[ctl_pin]);
    }
    // ready
    // ...
    
    nvmemprog.write_fpga_registers (0, (uint8[]) regs);
  }
  
  private void configure_fpga_registers_spi () throws DBError, UsbError {
    
  }
  
  
  // Interface config functions
  private void cfg_ifc_address_pin_mapping () throws DBError, UsbError {
    uint8[] addr_map = {};
    
    for (int i = ADDRESS_BUS_WIDTH_FX; i < ADDRESS_BUS_WIDTH_MAX; i++) {
      if (i == 9) {
        foreach (int pin_num in device.get_pin_numbers ("A9/Vid"))
          addr_map += (uint8) pin_num-1;
      } else {
        foreach (int pin_num in device.get_pin_numbers ("AddressBus", true, i))
          addr_map += (uint8) pin_num-1;
      }
    }
    nvmemprog.configure_memory_interface (NVMemProg.InterfaceConfigType.ADDRESS_PIN_MAPPING, addr_map, 0);
  }
  
  private void cfg_ifc_block_structure () throws DBError, UsbError {
    if (device.has_block_structure() == false)
      throw new DBError.ERROR ("Device has no defined block structure, required to configure interface");
    uint[] block_sizes = device.get_block_sizes ();
    uint current_addr = 0;
    uint8[] block_addr_serialized = new uint8[block_sizes.length*2];
    // convert size to address and serialize
    for (int i = 0; i < block_sizes.length*2; i += 2) {
      // little-endian format; divided by 512
      block_addr_serialized[i] = (uint8) ((current_addr / 512) & 0xFF);
      block_addr_serialized[i+1] = (uint8) ((current_addr / 512) >> 8);
      current_addr += block_sizes[i/2];
    }
    nvmemprog.configure_memory_interface (NVMemProg.InterfaceConfigType.BLOCK_STRUCTURE, block_addr_serialized, 0);
  }
  
  public void configure_interface_mx28f () throws DBError, UsbError {
    cfg_ifc_address_pin_mapping ();
  }
  
  public void configure_interface_27c512 () throws DBError, UsbError {
    cfg_ifc_address_pin_mapping ();
  }
  
  public void configure_interface_28f () throws DBError, UsbError {
    cfg_ifc_address_pin_mapping ();
    cfg_ifc_block_structure ();
  }
  
  public void configure_interface_am27 () throws DBError, UsbError {
    cfg_ifc_address_pin_mapping ();
  }
  
  public void configure_interface_29c () throws DBError, UsbError {
    cfg_ifc_address_pin_mapping ();
  }
}
