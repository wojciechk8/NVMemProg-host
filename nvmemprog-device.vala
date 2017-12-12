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

using NVMemProg;


public errordomain UsbError {
  LIBUSB_ERROR,
  INTERRUPTED,
  DEVICE_ERROR,
  DISCONNECTED
}

// Callback wrappers for libusb (UsbInterface instance is passed as user_data in transfer object)
private void cmd_transfer_callback_async (LibUSB.Transfer transfer) {
  ((UsbInterface) transfer.user_data).cmd_transfer_callback ();
}

private void cmd_transfer_callback_sync (LibUSB.Transfer transfer) {
  bool* completed = (bool*) transfer.user_data;
  *completed = true;
}

private void status_transfer_callback_async (LibUSB.Transfer transfer) {
  ((UsbInterface) transfer.user_data).status_transfer_callback ();
}

private void memory_transfer_callback_async (LibUSB.Transfer transfer) {
  ((UsbInterface) transfer.user_data).memory_transfer_callback ();
}


public class UsbInterface {
  private static LibUSB.Context context;
  private LibUSB.DeviceHandle dev_handle;
  private LibUSB.HotplugCallbackHandle hotplug_cb_handle;
  
  private LibUSB.Transfer cmd_transfer;
  private SourceFunc cmd_transfer_callback_fn;
  private bool transfer_completed;  // used for sync functions
  private uint8[] cmd_buffer;
  
  private LibUSB.Transfer status_transfer;
  private SourceFunc status_transfer_callback_fn;
  private uint8[] status_buffer;
  private const uint8 STATUS_ENDPOINT = 1;
  private const uint STATUS_TIMEOUT = 100;
  
  private LibUSB.Transfer memory_transfer;
  private SourceFunc memory_transfer_callback_fn;
  private const uint8 MEMORY_READ_ENDPOINT = 6;
  private const uint8 MEMORY_WRITE_ENDPOINT = 2;
  private const uint MEMORY_TRANSFER_TIMEOUT = 120000;
  
  Thread<void*> event_thread;
  private bool event_thread_run;
  
  public bool is_connected { get; private set; }
  public signal void device_connected ();
  public signal void device_disconnected ();
  
  
  public UsbInterface () throws UsbError {
    int rc = LibUSB.Context.init (out context);
    if (rc != LibUSB.Error.SUCCESS) {
      throw new UsbError.LIBUSB_ERROR (LibUSB.strerror ((LibUSB.Error) rc));
    }
    cmd_transfer = new LibUSB.Transfer ();
    status_transfer = new LibUSB.Transfer ();
    memory_transfer = new LibUSB.Transfer ();
    status_buffer = new uint8[sizeof(NVMemProg.DeviceStatus)];
  }
  
  ~UsbInterface () {
    if (event_thread_run) {
      if (dev_handle != null) {
        dev_handle.release_interface (0);
      }
      event_thread_run = false;
      context.hotplug_deregister_callback (hotplug_cb_handle);
      event_thread.join ();
    }
  }
  
  
  private void* event_thread_func () {
    while (event_thread_run) {
      context.handle_events_completed (null);
    }
    return null;
  }
  
  public void run_thread () throws Error {
    assert (event_thread_run == false);
    event_thread_run = true;
    event_thread = new Thread<void*> ("usb_event_thread", event_thread_func);
  }
  
  [CCode (instance_pos = 3.9)]
  public void hotplug_callback (LibUSB.Context context, LibUSB.Device device, LibUSB.HotplugEvent event) {
    int rc;
    switch (event) {
      case LibUSB.HotplugEvent.DEVICE_ARRIVED:
        rc = device.open (out dev_handle);
        if (rc != LibUSB.Error.SUCCESS) {
          warning ("Device arrived, but can't open\n");
          return;
        }
        rc = dev_handle.claim_interface (0);
        if (rc != LibUSB.Error.SUCCESS) {
          warning ("Device arrived, but can't claim interface 0\n");
          dev_handle = null;
          return;
        }
        status_transfer.fill_interrupt_transfer (dev_handle, LibUSB.EndpointDirection.IN | STATUS_ENDPOINT, status_buffer,
                                                 status_transfer_callback_async, this, STATUS_TIMEOUT);
        is_connected = true;
        device_connected ();
        break;
      
      case LibUSB.HotplugEvent.DEVICE_LEFT:
        dev_handle = null;
        is_connected = false;
        device_disconnected ();
        break;
      
      default:
        assert_not_reached ();
    }
  }
  
  public void register_hotplug () throws UsbError {
    if (LibUSB.has_capability (LibUSB.Capability.HAS_HOTPLUG) == 0) {
      throw new UsbError.LIBUSB_ERROR ("Hotplug not supported");
    }

    int rc = context.hotplug_register_callback (LibUSB.HotplugEvent.DEVICE_ARRIVED | LibUSB.HotplugEvent.DEVICE_LEFT,
                                                LibUSB.HotplugFlag.ENUMERATE, NVMemProg.VID, NVMemProg.PID, LibUSB.HOTPLUG_MATCH_ANY,
                                                (LibUSB.hotplug_callback_fn) hotplug_callback, out hotplug_cb_handle);
    if (rc != LibUSB.Error.SUCCESS) {
      throw new UsbError.LIBUSB_ERROR (LibUSB.strerror ((LibUSB.Error) rc));
    }
  }
  
  public void disconnect () {
    dev_handle = null;
    is_connected = false;
    device_disconnected ();
  }
  
  
  public void cmd_transfer_callback () {
    // Dispatch the callback in the main thread (we are now in usb event thread)
    Idle.add ((owned) cmd_transfer_callback_fn);
  }
  
  private void submit_transfer (LibUSB.Transfer transfer) throws UsbError {
    assert (dev_handle != null);
    int rc = transfer.submit ();
    if (rc != LibUSB.Error.SUCCESS) {
      throw new UsbError.LIBUSB_ERROR (LibUSB.strerror ((LibUSB.Error) rc));
    }
  }
  
  private void wait_for_transfer_completed () {
    while (!transfer_completed) {
      context.lock_event_waiters ();
      context.wait_for_event (null);
      context.unlock_event_waiters ();
    }
  }
  
  private void check_transfer_for_error (LibUSB.Transfer transfer) throws UsbError {
    switch (transfer.status) {
      case LibUSB.TransferStatus.COMPLETED:
        return;
      case LibUSB.TransferStatus.STALL:
        throw new UsbError.DEVICE_ERROR ("device error");
      case LibUSB.TransferStatus.TIMED_OUT:
        throw new UsbError.DEVICE_ERROR (LibUSB.strerror (LibUSB.Error.TIMEOUT));
      case LibUSB.TransferStatus.NO_DEVICE:
        throw new UsbError.DISCONNECTED (LibUSB.strerror (LibUSB.Error.NO_DEVICE));
      case LibUSB.TransferStatus.CANCELLED:
        return;
      default:
        throw new UsbError.LIBUSB_ERROR ("transfer error: %d".printf(cmd_transfer.status));
    }
  }
  
  public void cancel_command_transfer () {
    cmd_transfer.cancel ();
  }
  
  public void command (VendorCmd cmd, uint16 index, uint16 val, uint timeout = 100) throws UsbError {
    cmd_buffer = new uint8[LibUSB.CONTROL_SETUP_SIZE];
    LibUSB.Transfer.fill_control_setup (cmd_buffer, LibUSB.EndpointDirection.OUT | LibUSB.RequestType.VENDOR | LibUSB.RequestRecipient.DEVICE,
                                        cmd, val, index, 0);
    cmd_transfer.fill_control_transfer (dev_handle, cmd_buffer, cmd_transfer_callback_sync, &transfer_completed, timeout);
    transfer_completed = false;
    submit_transfer (cmd_transfer);
    wait_for_transfer_completed ();
    check_transfer_for_error (cmd_transfer);
  }
  
  public async void command_async (VendorCmd cmd, uint16 index, uint16 val, uint timeout = 200) throws UsbError {
    cmd_buffer = new uint8[LibUSB.CONTROL_SETUP_SIZE];
    cmd_transfer_callback_fn = command_async.callback;
    LibUSB.Transfer.fill_control_setup (cmd_buffer, LibUSB.EndpointDirection.OUT | LibUSB.RequestType.VENDOR | LibUSB.RequestRecipient.DEVICE,
                                        cmd, val, index, 0);
    cmd_transfer.fill_control_transfer (dev_handle, cmd_buffer, cmd_transfer_callback_async, this, timeout);
    submit_transfer (cmd_transfer);
    yield;
    check_transfer_for_error (cmd_transfer);
  }
  
  public void command_read (VendorCmd cmd, uint16 index, uint16 val, uint8[] data, uint timeout = 100) throws UsbError {
    cmd_buffer = new uint8[LibUSB.CONTROL_SETUP_SIZE + data.length];
    LibUSB.Transfer.fill_control_setup (cmd_buffer, LibUSB.EndpointDirection.IN | LibUSB.RequestType.VENDOR | LibUSB.RequestRecipient.DEVICE,
                                        cmd, val, index, (uint16) data.length);
    cmd_transfer.fill_control_transfer (dev_handle, cmd_buffer, cmd_transfer_callback_sync, &transfer_completed, timeout);
    transfer_completed = false;
    submit_transfer (cmd_transfer);
    wait_for_transfer_completed ();
    check_transfer_for_error (cmd_transfer);
    Memory.copy (data, &cmd_buffer[LibUSB.CONTROL_SETUP_SIZE], data.length);
  }
  
  public async void command_read_async (VendorCmd cmd, uint16 index, uint16 val, uint8[] data, uint timeout = 200) throws UsbError {
    cmd_buffer = new uint8[LibUSB.CONTROL_SETUP_SIZE + data.length];
    cmd_transfer_callback_fn = command_read_async.callback;
    LibUSB.Transfer.fill_control_setup (cmd_buffer, LibUSB.EndpointDirection.IN | LibUSB.RequestType.VENDOR | LibUSB.RequestRecipient.DEVICE,
                                        cmd, val, index, (uint16) data.length);
    cmd_transfer.fill_control_transfer (dev_handle, cmd_buffer, cmd_transfer_callback_async, this, timeout);
    submit_transfer (cmd_transfer);
    yield;
    check_transfer_for_error (cmd_transfer);
    Memory.copy (data, &cmd_buffer[LibUSB.CONTROL_SETUP_SIZE], data.length);
  }
  
  public void command_write (VendorCmd cmd, uint16 index, uint16 val, uint8[] data, uint timeout = 100) throws UsbError {
    cmd_buffer = new uint8[LibUSB.CONTROL_SETUP_SIZE + data.length];
    Memory.copy (&cmd_buffer[LibUSB.CONTROL_SETUP_SIZE], data, data.length);
    LibUSB.Transfer.fill_control_setup (cmd_buffer, LibUSB.EndpointDirection.OUT | LibUSB.RequestType.VENDOR | LibUSB.RequestRecipient.DEVICE,
                                        cmd, val, index, (uint16) data.length);
    cmd_transfer.fill_control_transfer (dev_handle, cmd_buffer, cmd_transfer_callback_sync, &transfer_completed, timeout);
    transfer_completed = false;
    submit_transfer (cmd_transfer);
    wait_for_transfer_completed ();
    check_transfer_for_error (cmd_transfer);
  }
  
  public async void command_write_async (VendorCmd cmd, uint16 index, uint16 val, uint8[] data, uint timeout = 200) throws UsbError {
    cmd_buffer = new uint8[LibUSB.CONTROL_SETUP_SIZE + data.length];
    Memory.copy (&cmd_buffer[LibUSB.CONTROL_SETUP_SIZE], data, data.length);
    cmd_transfer_callback_fn = command_write_async.callback;
    LibUSB.Transfer.fill_control_setup (cmd_buffer, LibUSB.EndpointDirection.OUT | LibUSB.RequestType.VENDOR | LibUSB.RequestRecipient.DEVICE,
                                        cmd, val, index, (uint16) data.length);
    cmd_transfer.fill_control_transfer (dev_handle, cmd_buffer, cmd_transfer_callback_async, this, timeout);
    submit_transfer (cmd_transfer);
    yield;
    check_transfer_for_error (cmd_transfer);
  }
  
  public void status_transfer_callback () {
    // Dispatch the callback in main thread (we are now in usb event thread)
    Idle.add ((owned) status_transfer_callback_fn);
  }
  
  public void cancel_status_transfer () {
    status_transfer.cancel ();
  }
  
  public async void status_read (uint8[] status) throws UsbError {
    status_transfer_callback_fn = status_read.callback;
    submit_transfer (status_transfer);
    yield;
    check_transfer_for_error (status_transfer);
    Memory.copy (status, status_buffer, status_buffer.length);
  }
  
  
  public void memory_transfer_callback () {
    // Dispatch the callback in main thread (we are now in usb event thread)
    Idle.add ((owned) memory_transfer_callback_fn);
  }
  
  public void cancel_memory_transfer () {
    memory_transfer.cancel ();
  }
  
  public async void memory_read_async (uint8[] buffer) throws UsbError {
    memory_transfer_callback_fn = memory_read_async.callback;
    memory_transfer.fill_bulk_transfer (dev_handle, LibUSB.EndpointDirection.IN | MEMORY_READ_ENDPOINT, buffer, 
                                        memory_transfer_callback_async, this, MEMORY_TRANSFER_TIMEOUT);
    submit_transfer (memory_transfer);
    yield;
    check_transfer_for_error (memory_transfer);
  }
  
  public async void memory_write_async (uint8[] buffer) throws UsbError {
    memory_transfer_callback_fn = memory_write_async.callback;
    memory_transfer.fill_bulk_transfer (dev_handle, LibUSB.EndpointDirection.OUT | MEMORY_WRITE_ENDPOINT, buffer, 
                                        memory_transfer_callback_async, this, MEMORY_TRANSFER_TIMEOUT);
    submit_transfer (memory_transfer);
    yield;
    check_transfer_for_error (memory_transfer);
  }
}


public class NVMemProgDevice : Object {
  private unowned UsbInterface usb;
  private bool last_ifc_busy;
  private bool last_sw_state;
  
  private const ulong FIRMWARE_LOAD_DELAY = 10000;
  private const uint16 CPUCS_ADDRESS = 0xE600;
  private const uint8 CPUCS_BIT_8051RES = 0x01;
  
  public const float VCC_MIN = 1.5f;
  public const float VPP_MIN = 7f;
  public const float VCC_MAX = 6.5f;
  public const float VPP_MAX = 15f;
  
  private const int TRANSFER_SIZE = 8*1024;
  public uint64 transferred { get; private set; }
  
  public bool is_ifc_busy { get; private set; }
  public signal void button_pressed ();
  public signal void overcurrent ();
  public signal void ifc_ready ();
  
  
  public NVMemProgDevice (UsbInterface usb) {
    this.usb = usb;
  }
  
  
  public void load_firmware (string filename) throws Error, UsbError {
    uint8 cpucs[1];
    var parser = new IHexParser ();
    parser.parse_file (filename);
    
    cpucs[0] = CPUCS_BIT_8051RES;
    usb.command_write (NVMemProg.VendorCmd.FIRMWARE_LOAD, 0, CPUCS_ADDRESS, cpucs);
    foreach (var record in parser.records) {
      if (record.type == IHexParser.Record.Type.DATA) {
        usb.command_write (NVMemProg.VendorCmd.FIRMWARE_LOAD, 0, record.addr, record.data);
      }
    }
    cpucs[0] = 0x00;
    usb.command_write (NVMemProg.VendorCmd.FIRMWARE_LOAD, 0, CPUCS_ADDRESS, cpucs);
    Thread.usleep (FIRMWARE_LOAD_DELAY);
  }
  
  public async void poll_status (Cancellable? cancellable = null) throws UsbError, IOError {
    DeviceStatus _status = DeviceStatus ();
    DeviceStatus *status = &_status;
    bool run = true;
    
    if (cancellable != null) {
      cancellable.connect ( () => {
        usb.cancel_status_transfer ();
      } );
    }
    
    while (run) {
      yield usb.status_read ((uint8[]) status);
      cancellable.set_error_if_cancelled ();
      
      if ((last_sw_state == false) && (status.sw != 0))
        button_pressed ();
      last_sw_state = (status.sw != 0);
      if (status.ocprot != 0)
        overcurrent ();
      if ((last_ifc_busy == true) && (status.ifc_busy == 0))
        ifc_ready ();
      is_ifc_busy = (status.ifc_busy != 0);
      last_ifc_busy = is_ifc_busy;
    }
  }
  
  public string get_firmware_signature () throws UsbError {
    uint8 buf[FW_SIGNATURE_SIZE];
    usb.command_read (NVMemProg.VendorCmd.FW_SIGNATURE, 0, 0, buf, 20);
    return (string) buf;
  }
  
  public uint8 get_driver_id () throws UsbError {
    uint8 id[1];
    usb.command_read (VendorCmd.DRIVER_READ_ID, 0, 0, id);
    return id[0];
  }
  
  public bool is_fpga_configured () throws UsbError {
    uint8 status[1];
    usb.command_read (VendorCmd.FPGA_GET_STATUS, 0, 0, status);
    return (status[0] == FpgaStatus.CONFIGURED);
  }
  
  public void configure_fpga (uint8[] rbf_data) throws UsbError {
    const int TRANSFER_SIZE = 1024;  // libusb allows max 4096 bytes data payload per control transfer
    int transferred = 0;
    
    usb.command (VendorCmd.FPGA_START_CONFIG, 0, 0);
    
    while (transferred < rbf_data.length) {
      int transfer_size = int.min(rbf_data.length - transferred, TRANSFER_SIZE);
      unowned uint8[] rbf_data_chunk = rbf_data[transferred:(transferred + transfer_size)];
      usb.command_write (VendorCmd.FPGA_WRITE_CONFIG, 0, 0, rbf_data_chunk);
      transferred += transfer_size;
    }

    if (is_fpga_configured () == false)
      throw new UsbError.DEVICE_ERROR ("FPGA configuration failed");
  }
  
  public void write_fpga_registers (uint8 reg_addr, uint8[] reg_data) throws UsbError {
    usb.command_write (VendorCmd.FPGA_WRITE_REGS, reg_addr, 0, reg_data);
  }
  
  public void configure_memory_interface (InterfaceConfigType type, uint8[]? config_data, uint8 param) throws UsbError {
    if (config_data != null)
      usb.command_write (VendorCmd.IFC_SET_CONFIG, type, param, config_data);
    else
      usb.command (VendorCmd.IFC_SET_CONFIG, type, param);
  }
  
  public void configure_driver (uint8[] config_data) throws UsbError {
    usb.command_write (VendorCmd.DRIVER_CONFIG, 0, 0, config_data);
  }
  
  public void configure_driver_pin (uint8 pin_num, DriverPinConfig cfg) throws UsbError {
    usb.command (VendorCmd.DRIVER_CONFIG_PIN, pin_num, cfg);
  }
  
  public void enable_driver () throws UsbError {
    usb.command (VendorCmd.DRIVER_ENABLE, 0, 0xA5);
  }
  
  public void disable_driver () throws UsbError {
    usb.command (VendorCmd.DRIVER_ENABLE, 0, 0);
  }
  
  public void switch_vpp (bool on) throws UsbError {
    usb.command (VendorCmd.PWR_SWITCH, PowerChannel.VPP, on ? 1 : 0);
  }
  
  public void switch_vcc (bool on) throws UsbError {
    usb.command (VendorCmd.PWR_SWITCH, PowerChannel.VCC, on ? 1 : 0);
  }
  
  public void reset_power () throws UsbError {
    usb.command (VendorCmd.PWR_RESET, 0, 0);
  }
  
  public void set_vpp (float voltage, float rate) throws UsbError
    requires (voltage >= VPP_MIN && voltage <= VPP_MAX)  // [V]
    requires (rate >= 0.0125f && rate <= 1.5f)           // [V/us]
  {
    uint16 _voltage = (uint16) Math.round (voltage * 16);
    uint16 _rate = (uint16) Math.round (rate / 0.0125f);
    usb.command (VendorCmd.PWR_SET_VOLTAGE, PowerChannel.VPP, (_rate<<8)|_voltage);
  }
  
  public void set_vcc (float voltage, float rate) throws UsbError
    requires (voltage >= VCC_MIN && voltage <= VCC_MAX)  // [V]
    requires (rate >= 0.00625f && rate <= 0.75f)         // [V/us]
  {
    uint16 _voltage = (uint16) Math.round (voltage * 16);
    uint16 _rate = (uint16) Math.round (rate / 0.00625f);
    usb.command (VendorCmd.PWR_SET_VOLTAGE, PowerChannel.VCC, (_rate<<8)|_voltage);
  }
  
  public void set_ipp (uint current) throws UsbError
    requires (current >= 10 && current <= 250)      // [mA]
  {
    usb.command (VendorCmd.PWR_SET_CURRENT, PowerChannel.IPP, (uint16) current);
  }
  
  public void set_icc (uint current) throws UsbError
    requires (current >= 20 && current <= 500)      // [mA]
  {
    usb.command (VendorCmd.PWR_SET_CURRENT, PowerChannel.ICC, (uint16) current/2);
  }
  
  public async uint8[] read_memory_id (InterfaceIdType id_type, int length, Cancellable? cancellable = null) throws UsbError, IOError {
    uint8[] id = new uint8[length];
    if (cancellable != null)
      cancellable.connect ( () => { usb.cancel_command_transfer (); } );
    yield usb.command_read_async (VendorCmd.IFC_READ_ID, id_type, 0, id, 500);
    if (cancellable != null)
      cancellable.set_error_if_cancelled ();
    return id;
  }
  
  public async void read_memory_data (OutputStream data_stream, uint64 size, Cancellable? cancellable = null) throws UsbError, IOError {
    const int TRANSFER_SIZE = 64*1024;
    uint8[] buffer = new uint8[TRANSFER_SIZE];
    
    if (cancellable != null) {
      cancellable.connect ( () => {
        usb.cancel_memory_transfer ();
      } );
    }
    
    usb.command (VendorCmd.IFC_READ_DATA, 0, 0);
    
    transferred = 0;
    while (transferred < size) {
      if ((size - transferred) < TRANSFER_SIZE)
        buffer.resize ((int)(size - transferred));
      yield usb.memory_read_async (buffer);
      cancellable.set_error_if_cancelled ();
      ssize_t written = 0;
      while (written < buffer.length) {
        written += yield data_stream.write_async (buffer[written:buffer.length], Priority.DEFAULT, cancellable);
        cancellable.set_error_if_cancelled ();
      }
      transferred += uint64.min (TRANSFER_SIZE, size - transferred);
    }
  }
  
  public async void write_memory_data (InputStream data_stream, uint64 size, Cancellable? cancellable = null) throws UsbError, IOError {
    uint8[] buffer = new uint8[TRANSFER_SIZE];
    
    if (cancellable != null) {
      cancellable.connect ( () => {
        usb.cancel_memory_transfer ();
      } );
    }
    
    usb.command (VendorCmd.IFC_WRITE_DATA, 0, 0);
    
    transferred = 0;
    while (transferred < size) {
      if ((size - transferred) < TRANSFER_SIZE)
        buffer.resize ((int)(size - transferred));
      yield data_stream.read_async (buffer, Priority.DEFAULT, cancellable);
      cancellable.set_error_if_cancelled ();
      yield usb.memory_write_async (buffer);
      cancellable.set_error_if_cancelled ();
      transferred += uint64.min (TRANSFER_SIZE, size - transferred);
    }
    
    ulong handler_id = ifc_ready.connect ( () => { write_memory_data.callback (); } );
    cancellable.connect ( () => { write_memory_data.callback (); } );
    yield;
    disconnect (handler_id);
  }
  
  public async bool verify_memory_data (InputStream data_stream, uint64 size, uint64* error_offset, Cancellable? cancellable = null) throws UsbError, IOError {
    uint8[] buffer = new uint8[TRANSFER_SIZE];
    uint8[] buffer_ver = new uint8[TRANSFER_SIZE];
    
    if (cancellable != null) {
      cancellable.connect ( () => {
        usb.cancel_memory_transfer ();
      } );
    }
    
    usb.command (VendorCmd.IFC_READ_DATA, 0, 0);
    
    transferred = 0;
    while (transferred < size) {
      if ((size - transferred) < TRANSFER_SIZE)
        buffer.resize ((int)(size - transferred));
      yield usb.memory_read_async (buffer);
      cancellable.set_error_if_cancelled ();
      yield data_stream.read_async (buffer_ver, Priority.DEFAULT, cancellable);
      cancellable.set_error_if_cancelled ();
      for (int i = 0; i < buffer.length; i++) {
        if (buffer[i] != buffer_ver[i]) {
          *error_offset = transferred + i;
          return false;
        }
      }
      transferred += uint64.min (TRANSFER_SIZE, size - transferred);
    }
    return true;
  }
  
  public async bool erase_chip (uint erase_time, Cancellable? cancellable = null) throws UsbError, IOError {
    bool erased = false;
    uint timeout_id = 0;
    if (cancellable != null)
      cancellable.connect ( () => {
        erase_chip.callback ();
      } );
    ulong ready_handler_id = ifc_ready.connect ( () => {
      erased = true;
      erase_chip.callback ();
    } );
    timeout_id = Timeout.add (erase_time, () => {
      timeout_id = 0;
      erase_chip.callback ();
      return Source.REMOVE;
    } );
    usb.command (VendorCmd.IFC_ERASE_CHIP, 0, 0);
    yield;
    if (timeout_id != 0)
      Source.remove (timeout_id);
    disconnect (ready_handler_id);
    if (cancellable != null)
      cancellable.set_error_if_cancelled ();
    return erased;
  }
  
  public void abort_memory_operation () throws UsbError {
    usb.command (VendorCmd.IFC_ABORT, 0, 0);
  }
  
  public async bool blank_check (uint64 size, uint64* error_offset, Cancellable? cancellable = null) throws UsbError, IOError {
    uint8[] buffer = new uint8[TRANSFER_SIZE];
    
    if (cancellable != null) {
      cancellable.connect ( () => {
        usb.cancel_memory_transfer ();
      } );
    }
    
    usb.command (VendorCmd.IFC_READ_DATA, 0, 0);
    
    transferred = 0;
    while (transferred < size) {
      if ((size - transferred) < TRANSFER_SIZE)
        buffer.resize ((int)(size - transferred));
      yield usb.memory_read_async (buffer);
      cancellable.set_error_if_cancelled ();
      for (int i = 0; i < buffer.length; i++) {
        if (buffer[i] != 0xFF) {
          *error_offset = transferred + i;
          return false;
        }
      }
      transferred += uint64.min (TRANSFER_SIZE, size - transferred);
    }
    return true;
  }
}
