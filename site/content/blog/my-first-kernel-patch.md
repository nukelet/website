+++
title = "My first kernel patch: fixing a broken bluetooth dongle"
date = "2024-04-20"
description = "A debugging diary of how I wrote my first kernel patch."
draft = false
tags = [
    "linux",
    "kernel",
]
+++

# TL;DR

I bought a cheap Bluetooth USB dongle from AliExpress, and really wanted to use it, but it wouldn't connect to any devices on Linux. I was looking to get started with contributing to the kernel and decided to tackle this problem and potentially send my first patch.

The issue was that the controller erroneously reported support for the `Read Encryption Key Size` HCI command; when the kernel tried to follow the standard and run it during the key exchange that happens when connecting to BT devices, the controller would bail out and the connection would fail. This worked fine on Windows because it straight up doesn't run this key size check (even though it is supposed to).

The fix was simply adding a new quirk to hint that the controller doesn't actually support the command. [The patch](https://lore.kernel.org/all/20240227014328.1052386-1-nukelet64@gmail.com/) was merged upstream and backported to Linux 6.8 and 6.6! This was my first patch to the kernel, and I was really happy to have it fix a real problem for me and [other users](https://bugzilla.kernel.org/show_bug.cgi?id=217870#c3) of the USB dongle. :-)

The following is a "diary" of sorts where I recorded my thought process while investigating and fixing the issue. It's all over the place, but maybe it will provide some sort of insight to someone investigating a similar issue? :')

# Debugging diary

I'll try to record my adventures debugging a broken bluetooth USB dongle on Linux.

From the Aliexpress product page, it's a "Baseus-BA07 USB Bluetooth 5.3 Dongle Adapter". It comes with the Actions Semi ATS2851 chipset, which has apparently been a source of [headaches](https://marc.info/?l=linux-bluetooth&w=2&r=1&s=ats2851&q=b) for the kernel bluetooth folks.

I have an Edifier 820NB bluetooth headset. It's great, has a huge battery life, and the audio quality is pretty good. I wear it pretty much 24/7 when I'm outside, and would like to get it working with my dongle.

However, when trying to connect to the headset, I get very weird behavior from the dongle. When trying to connect to it in KDE Plasma, the widget says it is connected, but the headset doesn't show up as an audio output. Also, after a little while, the headset seems to disconnect.

## 2024-02-24

Upon taking a closer look at the BT packet exchange with `bluetoothctl` and `btmon`, it gets a little weirder when we try to connect to the headset：

```
> HCI Event: User Confirmation Request (0x33) plen 10                                                      #39 [hci0] 6.408429
        Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
        Passkey: 386942
@ MGMT Event: User Confirmation Request (0x000f) plen 12                                              {0x0001} [hci0] 6.408454
        BR/EDR Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
        Confirm hint: 0x01
        Value: 0x0005e77e
bluetoothd[1217]: @ MGMT Command: User Confirmation Negative Reply (0x001d) plen 7                    {0x0001} [hci0] 6.408513
        BR/EDR Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
< HCI Command: User Confirmation Request Neg Reply (0x01|0x002d) plen 6                                    #40 [hci0] 6.408523
        Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
> HCI Event: Command Status (0x0f) plen 4                                                                  #41 [hci0] 6.410258
      User Confirmation Request Neg Reply (0x01|0x002d) ncmd 1
        Status: Unknown HCI Command (0x01)
< ACL Data TX: Handle 2048 flags 0x00 dlen 12                                                              #42 [hci0] 8.215009
      L2CAP: Disconnection Request (0x06) ident 4 len 4
        Destination CID: 65
        Source CID: 64
```

It would seem that we receive an "User Confirmation Request (0x33)" HCI event, and for some reason decide to reply with a negative reply.

After a lot of struggle with `virt-manager`, I set up a Windows 11 VM with USB passthrough for the dongle just to capture this initial packet exchange on Wireshark and compare it with the Linux one, and I noticed that this specific HCI event doesn't happen on Windows at all ~~(which is kinda funny, because it was sent **by the device** to the host)~~. We'll need to investigate this further, I guess.

**Note**: upon looking closely at the Wireshark dump from Linux, this error message is actually sent from the _controller_ (i.e. the USB dongle) to the _host_ (i.e., the machine the dongle is connected to). Neat! Now at the very least we know it's an issue with the dongle, and not the headset.

Upon looking at the kernel source, I noticed the following:

1. The ATS2851 chipset is defined in `drivers/bluetooth/btusb.c`: 

```c
       { USB_DEVICE(0x10d7, 0xb012), .driver_info = BTUSB_ACTIONS_SEMI },
```

2. The chipset seems to report features that it doesn't actually support; this has been accounted for by adding chipset-specific quirks to the device:
```c
	if (id->driver_info & BTUSB_ACTIONS_SEMI) {
		/* Support is advertised, but not implemented */
		set_bit(HCI_QUIRK_BROKEN_ERR_DATA_REPORTING, &hdev->quirks);
		set_bit(HCI_QUIRK_BROKEN_READ_TRANSMIT_POWER, &hdev->quirks);
		set_bit(HCI_QUIRK_BROKEN_SET_RPA_TIMEOUT, &hdev->quirks);
		set_bit(HCI_QUIRK_BROKEN_EXT_SCAN, &hdev->quirks);
	}
```

These quirk flags seem to be checked in various functions within `net/bluetooth` and alter the way the kernel responds to HCI commands/events.

3. The kernel stores a table of callbacks for each event:

```c
static const struct hci_ev {
	bool req;
	union {
		void (*func)(struct hci_dev *hdev, void *data,
			     struct sk_buff *skb);
		void (*func_req)(struct hci_dev *hdev, void *data,
				 struct sk_buff *skb, u16 *opcode, u8 *status,
				 hci_req_complete_t *req_complete,
				 hci_req_complete_skb_t *req_complete_skb);
	};
	u16  min_len;
	u16  max_len;
} hci_ev_table[U8_MAX + 1] = {
	...

	/* [0x33 = HCI_EV_USER_CONFIRM_REQUEST] */
	HCI_EV(HCI_EV_USER_CONFIRM_REQUEST, hci_user_confirm_request_evt,
	       sizeof(struct hci_ev_user_confirm_req)),

	...
};
```

Side note, but the `HCI_EV` macro actually blew my mind a little bit:

```c
#define HCI_EV_VL(_op, _func, _min_len, _max_len) \
[_op] = { \
	.req = false, \
	.func = _func, \
	.min_len = _min_len, \
	.max_len = _max_len, \
}

#define HCI_EV(_op, _func, _len) \
	HCI_EV_VL(_op, _func, _len, _len)
```

This is possible because apparently in C there's this arcane way of initializing arrays using _designators_ ([reference](https://en.cppreference.com/w/c/language/array_initialization)):

```c
int n[5] = {[4]=5,[0]=1,2,3,4}; // holds 1,2,3,4,5
```

which allows you to initialize specific elements by index. Several years of C programming and I had never heard of this. TIL.

At this point I took a look at the `hci_user_confirm_request_evt` callback and noticed it had a bunch of debug log messages that could prove useful. I then tried to investigate if there was a way to change the log level for a specific module (setting the whole kernel to debug level would flood `dmesg` massively, I think). Turns out the kernel has this really cool feature called [_dynamic debugging_](https://docs.kernel.org/admin-guide/dynamic-debug-howto.html?highlight=dynamic+debug), which allows you to do just that (in fact, you can change the log level for specific `.c` files, which I think is super neat). [This stack overflow answer](https://stackoverflow.com/questions/50504516/enable-linux-kernel-driver-dev-dbg-debug-messages) summarizes it nicely. I managed to enable debug logs for `hci_event.c` with the following command:

```bash
echo 'file net/bluetooth/hci_event.c +p' > /sys/kernel/debug/dynamic_debug/control
```

Looking at `dmesg`, I noticed the following messages associated with event 0x33:

```
[Sat Feb 24 21:21:38 2024] hci0: event 0x33
[Sat Feb 24 21:21:38 2024] hci0: 
[Sat Feb 24 21:21:38 2024] hci0: Local host already has link key
```

That came from this piece of code inside `hci_user_confirm_request_evt`:

```c
	/* If no side requires MITM protection; auto-accept */
	if ((!loc_mitm || conn->remote_cap == HCI_IO_NO_INPUT_OUTPUT) &&
	    (!rem_mitm || conn->io_capability == HCI_IO_NO_INPUT_OUTPUT)) {

		...

		/* If there already exists link key in local host, leave the
		 * decision to user space since the remote device could be
		 * legitimate or malicious.
		 */
		if (hci_find_link_key(hdev, &ev->bdaddr)) {
			bt_dev_dbg(hdev, "Local host already has link key");
			confirm_hint = 1;
			goto confirm;
		}

		...

	}

	confirm:
		mgmt_user_confirm_request(hdev, &ev->bdaddr, ACL_LINK, 0,
					  le32_to_cpu(ev->passkey), confirm_hint);

	...

```

This suggests that userspace is choosing to refuse the User Confirm Request.

## 2024-02-25

It's a bright new day (well, afternoon) and the debugging continues. I managed to find the piece of code that (I think) controls the controls the `User Confirm Request` stuff in [bluez](https://github.com/bluez/bluez) (`src/device.c`):

```c
int device_confirm_passkey(struct btd_device *device, uint8_t type,
					int32_t passkey, uint8_t confirm_hint)
{
	...

	/* Just-Works repairing policy */
	if (confirm_hint && device_is_paired(device, type)) {
		if (btd_opts.jw_repairing == JW_REPAIRING_NEVER) {
			btd_adapter_confirm_reply(device->adapter,
						  &device->bdaddr,
						  type, FALSE);
			return 0;
		} else if (btd_opts.jw_repairing == JW_REPAIRING_ALWAYS) {
			btd_adapter_confirm_reply(device->adapter,
						  &device->bdaddr,
						  type, TRUE);
			return 0;
		}
	}

	...
}
```

This behavior is controlled by the `JustWorksRepairing` option in `/etc/bluetooth/main.conf`. Now, this is a dirty hack, but since the controller doesn't support the `User Confirm Request Negative Reply` command, we can work around it with the config option. Setting `JustWorksRepairing = always` actually works, and the connection advances (yay!).

**Note**: should patch this in the kernel later (adding a quirk that hints that this command is not supported).

However, we reach yet another roadblock™:

```
< HCI Command: Set Connection Encryption (0x01|0x0013) plen 3                                           #103 [hci0] 108.211268
        Handle: 2048 Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
        Encryption: Enabled (0x01)
> HCI Event: Command Status (0x0f) plen 4                                                               #104 [hci0] 108.213088
      Set Connection Encryption (0x01|0x0013) ncmd 1
        Status: Success (0x00)
> HCI Event: Encryption Change (0x08) plen 4                                                            #105 [hci0] 108.302269
        Status: Success (0x00)
        Handle: 2048 Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
        Encryption: Enabled with E0 (0x01)
< HCI Command: Read Encryption Key Size (0x05|0x0008) plen 2                                            #106 [hci0] 108.302299
        Handle: 2048 Address: 0C:AE:BD:5E:B2:A0 (Edifier International)
> HCI Event: Command Status (0x0f) plen 4                                                               #107 [hci0] 108.304100
      Read Encryption Key Size (0x05|0x0008) ncmd 1
        Status: Unknown HCI Command (0x01)
```

Yet another command that the dongle doesn't support. From looking at the kernel source, I found that the only place where this command (`HCI_OP_READ_ENC_KEY_SIZE`) is invoked is in `net/bluetooth/hci_event.c`:

```c
static void hci_encrypt_change_evt(struct hci_dev *hdev, void *data,
				   struct sk_buff *skb)
{
	...

	/* Try reading the encryption key size for encrypted ACL links */
	if (!ev->status && ev->encrypt && conn->type == ACL_LINK) {
		struct hci_cp_read_enc_key_size cp;

		/* Only send HCI_Read_Encryption_Key_Size if the
		 * controller really supports it. If it doesn't, assume
		 * the default size (16).
		 */
		if (!(hdev->commands[20] & 0x10)) {
			conn->enc_key_size = HCI_LINK_KEY_SIZE;
			goto notify;
		}

		cp.handle = cpu_to_le16(conn->handle);
		if (hci_send_cmd(hdev, HCI_OP_READ_ENC_KEY_SIZE,
				 sizeof(cp), &cp)) {
			bt_dev_err(hdev, "sending read key size failed");
			conn->enc_key_size = HCI_LINK_KEY_SIZE;
			goto notify;
		}

		goto unlock;
	}

	...
	
	notify:
		hci_encrypt_cfm(conn, ev->status);
	
	unlock:
		hci_dev_unlock(hdev);
	}
}
```

I quickly put together a small patch that adds a new quirk to cover this:

```diff
diff --git a/drivers/bluetooth/btusb.c b/drivers/bluetooth/btusb.c
index d31edad7a056..0c0e06ea9286 100644
--- a/drivers/bluetooth/btusb.c
+++ b/drivers/bluetooth/btusb.c
@@ -4481,6 +4481,7 @@ static int btusb_probe(struct usb_interface *intf,
 		set_bit(HCI_QUIRK_BROKEN_READ_TRANSMIT_POWER, &hdev->quirks);
 		set_bit(HCI_QUIRK_BROKEN_SET_RPA_TIMEOUT, &hdev->quirks);
 		set_bit(HCI_QUIRK_BROKEN_EXT_SCAN, &hdev->quirks);
+		set_bit(HCI_QUIRK_BROKEN_READ_ENC_KEY_SIZE, &hdev->quirks);
 	}
 
 	if (!reset)
diff --git a/include/net/bluetooth/hci.h b/include/net/bluetooth/hci.h
index bdee5d649cc6..8c36e094ec99 100644
--- a/include/net/bluetooth/hci.h
+++ b/include/net/bluetooth/hci.h
@@ -330,6 +330,14 @@ enum {
 	* during the hdev->setup vendor callback.
 	*/
 	HCI_QUIRK_BROKEN_LE_CODED,
+
+	/*
+	* When this quirk is set, the HCI_OP_READ_ENC_KEY_SIZE command is
+	* skipped during an HCI_EV_ENCRYPT_CHANGE event. This is required
+	* for Actions Semiconductor ATS2851 based controllers, which erroneously
+	* claim to support it.
+	*/
+	HCI_QUIRK_BROKEN_READ_ENC_KEY_SIZE,
 };
 
 /* HCI device flags */
diff --git a/net/bluetooth/hci_event.c b/net/bluetooth/hci_event.c
index ef8c3bed7361..399f983bbb1d 100644
--- a/net/bluetooth/hci_event.c
+++ b/net/bluetooth/hci_event.c
@@ -3660,7 +3660,8 @@ static void hci_encrypt_change_evt(struct hci_dev *hdev, void *data,
 		* controller really supports it. If it doesn't, assume
 		* the default size (16).
 		*/
-		if (!(hdev->commands[20] & 0x10)) {
+		if (!(hdev->commands[20] & 0x10) ||
+		   test_bit(HCI_QUIRK_BROKEN_READ_ENC_KEY_SIZE, &hdev->quirks)) {
 			conn->enc_key_size = HCI_LINK_KEY_SIZE;
 			goto notify;
 		}
```

Update: after spinning up the patched kernel on a Debian VM with USB passthrough (thanks `virt-manager`), this actually works! The headset connects and audio works just fine now. Curiously enough, the `User Confirm Request Negative Reply` issue didn't happen at all. I'm still debating whether I should just add another quirk for it in the patch, but maybe it was just a red herring?

I will look for guidance about cleaning this up and sending it as a patch for upstream. Very exciting!

Also, huge shoutout to the FLUSP folks for [this guide](https://flusp.ime.usp.br/kernel/Kernel-compilation-and-installation/). It was very helpful.
