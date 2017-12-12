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


[CCode (cheader_filename = "common.h")]
namespace NVMemProg {
  [CCode (cname = "VID")]
  public const uint16 VID;
  [CCode (cname = "PID")]
  public const uint16 PID;
  [CCode (cname = "FW_SIGNATURE_SIZE")]
  public const uint FW_SIGNATURE_SIZE;
  
  [SimpleType]
  [CCode (cname = "BYTE", has_type_id = false)]
  public struct BYTE : uint8 { }
  [SimpleType]
  [CCode (cname = "WORD", has_type_id = false)]
  public struct WORD : uint16 {}
  [SimpleType]
  [CCode (cname = "DWORD", has_type_id = false)]
  public struct DWORD : uint32 { }
  

  [CCode (cname = "VENDOR_CMD", cprefix = "CMD_", has_type_id = false)]
  public enum VendorCmd {
    LED,
    FW_SIGNATURE,
    FPGA_START_CONFIG,
    FPGA_WRITE_CONFIG,
    FPGA_GET_STATUS,
    FPGA_READ_REGS,
    FPGA_WRITE_REGS,
    DRIVER_READ_ID,
    DRIVER_WRITE_ID,
    DRIVER_CONFIG,
    DRIVER_CONFIG_PIN,
    DRIVER_ENABLE,
    PWR_SET_DAC,
    PWR_SET_VOLTAGE,
    PWR_SET_CURRENT,
    PWR_SWITCH,
    PWR_RESET,
    PWR_SW_STATE,
    EEPROM_READ,
    EEPROM_WRITE,
    IFC_SET_CONFIG,
    IFC_READ_ID,
    IFC_ERASE_CHIP,
    IFC_READ_DATA,
    IFC_WRITE_DATA,
    IFC_ABORT,
    FIRMWARE_LOAD
  }
  
  
  [CCode (cname = "FPGA_CFG_STATUS", cprefix = "FPGA_STATUS_", has_type_id = false)]
  public enum FpgaStatus {
    UNCONFIGURED,
    CONFIGURING,
    CONFIGURED
  }
  
  [Compact, CCode (cname = "FPGA_UNIV_REGISTERS")]
  public struct FpgaUnivRegisters {
    public uint8 mem_mux_selector[48];
    public uint8 rdy_fx_mux_selector[2];
  }
  
  [CCode (cname = "FPGA_UNIV_MEM_MUX_SELECTOR", cprefix = "FPGA_UNIV_MUX_", has_type_id = false)]
  public enum FpgaUnivMuxSelector {
    DATA_FX,
    ADDR_FX,
    CTL_FX,
    LOW,
    HIGH
  }
  [CCode (cname = "FPGA_UNIV_MUX_ENABLE")]
  public const uint8 FPGA_UNIV_MUX_ENABLE;
  
  
  [CCode (cname = "PWR_CH", cprefix = "PWR_CH_", has_type_id = false)]
  public enum PowerChannel {
    VPP,
    VCC,
    IPP,
    ICC
  }
  
  
  [CCode (cname = "DRIVER_ID", cprefix = "DRIVER_ID_", has_type_id = false)]
  public enum DriverId {
    DEFAULT
  }
  
  [CCode (cname = "DRIVER_PIN_CONFIG", cprefix = "DRIVER_PIN_CONFIG_", has_type_id = false)]
  public enum DriverPinConfig {
    IO,
    GND,
    VCC,
    VPP
  }
  [CCode (cname = "DRIVER_PIN_CONFIG_PULL_UP_ENABLE")]
  public const uint8 DRIVER_PIN_CONFIG_PULL_UP_ENABLE;
  [CCode (cname = "DRIVER_PIN_CONFIG_PULL_UP_DISABLE")]
  public const uint8 DRIVER_PIN_CONFIG_PULL_UP_DISABLE;
  [CCode (cname = "DRIVER_CONFIG")]
  public struct DriverConfig {
    public uint8 pin_config[48];
  }
  
  
  [CCode (cname = "DEVICE_STATUS")]
  public struct DeviceStatus {
    public uint8 sw;
    public uint8 ocprot;
    public uint8 ifc_busy;
  }


  [CCode (cname = "IFC_CFG_TYPE", cprefix = "IFC_CFG_", has_type_id = false)]
  public enum InterfaceConfigType {
    ADDRESS_PIN_MAPPING,
    BLOCK_STRUCTURE
  }
  
  [CCode (cname = "IFC_ID_TYPE", cprefix = "IFC_ID_", has_type_id = false)]
  public enum InterfaceIdType {
    MANUFACTURER,
    DEVICE,
    CAPACITY,
    EXTENDED
  }
}
