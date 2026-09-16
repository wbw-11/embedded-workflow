---
name: vm-error-recovery
version: 1.0.0
description: "诊断 QoderWork 安全工作区启动错误：启动失败/连接问题/下载问题，给出可操作恢复步骤。"
description_zh: "诊断并引导用户自行修复安全工作环境准备错误。当用户提到安全工作环境启动失败、无法连接、下载出错或任何安全工作环境相关异常时使用。"
---

# Secure Workspace Error Recovery

Guide users through diagnosing and fixing secure workspace startup errors. Never expose internal implementation details — focus on actionable steps in plain language.

## Diagnostic Procedure

### Step 1: Read the Diagnostic File

Use the `Read` tool to read the diagnostic state file:

```
~/{{.DataDirName}}/vm/boot-state.json
```

This file contains:

```json
{
  "boot_id": "boot_...",
  "status": "booting | ready | failed | stopped",
  "error": {
    "phase": "...",
    "code": "...",
    "message": "...",
    "errorKey": "the_key_to_match_below"
  },
  "environment": {
    "platform": "darwin | windows",
    "arch": "x64 | arm64",
    "os_version": "...",
    "qoderwork_version": "..."
  },
  "phases": { ... }
}
```

### Step 2: Identify the Error

Extract `error.errorKey` from the JSON. If the file does not exist or cannot be read, skip to the **Fallback** section below.

### Step 3: Look Up Recovery Instructions

Match the `errorKey` against the tables below. Use `environment.platform` to determine whether to give Windows-specific or macOS-specific instructions.

### Step 4: Guide the User

- Use **plain, non-technical language** — never mention internal component names.
- Use the user's language (Chinese / English) matching their conversation.
- When the recovery involves opening a settings page, use the Connector to help (see **Connector Actions** below).

---

## Error Recovery Reference

### Category A: Simple Retry

These errors are typically transient. Guide the user with simple, non-technical retry steps.

---

#### A1: Startup Timed Out or Stuck

**Error keys:** `hcs_timeout`, `hcs_service_timeout`, `hcs_unexpected`, `hcs_unknown`, `channels_ready_timeout`, `health_check_timeout`

**What to tell the user:**

> Your secure workspace took too long to start, likely because the system is busy.
>
> 1. Close other programs that may be using a lot of resources (games, video editors, multiple browser tabs, etc.)
> 2. Restart QoderWork and try again
> 3. If it happens again, restart your computer and then try

---

#### A2: Insufficient System Resources

**Error keys:** `hcs_insufficient_resources`

**What to tell the user:**

> Your computer does not have enough available memory to start the secure workspace.
>
> 1. Close memory-heavy programs — browsers with many tabs, large apps, etc.
> 2. Restart QoderWork and try again
> 3. If this keeps happening, your computer may not have enough memory for this feature. Consider upgrading your memory (the secure workspace needs at least 2 GB of free memory on Windows, 4 GB on macOS).

---

#### A3: Startup Unexpectedly Interrupted

**Error keys:** `guest_init_failed`, `hvkit_exit_unexpected`, `vm_start_failed`, `vm_process_exited`

**What to tell the user:**

> The secure workspace startup was unexpectedly interrupted.
>
> 1. Restart QoderWork and try again
> 2. If it happens repeatedly, restart your computer and then try
> 3. If it still fails after restarting, click the feedback button (top-right corner) to report the issue

---

#### A4: Network or Download Issues

**Error keys:** `manifest_network_error`, `download_network_error`, `download_timeout`, `download_http_error`, `download_aborted`, `download_wait_timeout`, `download_unknown`

**What to tell the user:**

> The download failed due to a network issue.
>
> 1. Check that your internet connection is working (try opening a website in your browser)
> 2. If you are using a VPN or proxy, try disabling it temporarily
> 3. Make sure QoderWork stays open and your network stays connected, then try again

---

#### A5: Server Resource Temporarily Unavailable

**Error keys:** `download_resource_not_found`

**What to tell the user:**

> The required resource is temporarily unavailable on the server.
>
> 1. Wait a few minutes and try again
> 2. If the problem persists after several attempts, click the feedback button (top-right corner) to report the issue

---

#### A6: Download File Verification Failed

**Error keys:** `download_checksum_mismatch`

**What to tell the user:**

> The downloaded file appears to be corrupted during transfer. This is usually a one-time issue.
>
> 1. Try downloading again — it will usually succeed on the next attempt
> 2. If it fails repeatedly, check your network connection or try a different network

---

#### A7: Insufficient Permissions (Windows)

**Error keys:** `hcs_access_denied`

**What to tell the user:**

> QoderWork needs administrator privileges to start the secure workspace.
>
> 1. Close QoderWork
> 2. Right-click the QoderWork icon and select **"Run as administrator"**
> 3. Try again

---

### Category B: Specific Actions Required

These errors require the user to perform specific operations (settings changes, commands, or disk cleanup).

---

#### B1: Workspace Files Missing or Corrupted

**Error keys:** `image_not_found`, `disk_not_found`, `path_validate_failed`, `vf_start_failed`, `resource_detect_failed`, `hvkit_permission_denied`

**What to tell the user:**

> Some required secure workspace files are missing or damaged.
>
> 1. Open **Settings** > **Secure Workspace** tab
> 2. Click **"Clean Workspace"** and confirm
> 3. Wait for the files to re-download automatically
> 4. Try starting the secure workspace again

**Connector shortcut:** Use the Connector to open the VM settings page directly (see Connector Actions below).

---

#### B2: Not Enough Disk Space

**Error keys:** `download_disk_full`

**What to tell the user:**

> There is not enough disk space to download the required files. The secure workspace needs about 20 GB of free space.
>
> 1. Free up disk space by deleting unnecessary files, emptying the Recycle Bin / Trash, or uninstalling unused programs
> 2. Make sure you have at least **20 GB** of free space
> 3. Try again

---

#### B3: Security Software Blocking

**Error keys:** `download_extract_failed`

**What to tell the user:**

> File extraction failed, possibly because security software (antivirus) is blocking it.
>
> 1. Add QoderWork to your security software's **trusted / allowed list**
> 2. Open **Settings** > **Secure Workspace** tab > click **"Clean Workspace"**
> 3. Wait for the files to re-download and try again

---

#### B4: Windows Virtualization Not Enabled

**Error keys:** `win_hyperv_not_enabled`

**What to tell the user:**

> The secure workspace requires a Windows feature called Hyper-V, which is not yet enabled on your computer.
>
> 1. Open **Control Panel** > **Programs** > **"Turn Windows features on or off"**
> 2. Find and check **Hyper-V** in the list
> 3. Click **OK** and **restart your computer**
>
> **Note:** Windows Home edition may not support Hyper-V. If you don't see Hyper-V in the list, your Windows edition may not be compatible. Click the feedback button (top-right corner) for further assistance.

**Error keys:** `hcs_not_found`, `hcs_dependency_missing`

For these two keys, the Hyper-V components are missing or damaged. Provide the same guidance as above, and additionally offer this command for advanced users:

> If the above steps don't work, you can try running this command as Administrator in **PowerShell**:
>
> ```
> dism.exe /Online /Enable-Feature /FeatureName:Microsoft-Hyper-V /All
> ```
>
> Then restart your computer.
>
> If the problem persists, try running this system repair command as well:
>
> ```
> sfc /scannow
> ```

---

#### B5: Required Windows Service Missing

**Error keys:** `hcs_service_not_installed`

**What to tell the user:**

> A required system service is missing. This usually means the installation was incomplete.
>
> 1. Uninstall QoderWork completely
> 2. Re-download and reinstall QoderWork **with administrator privileges**, and DO NOT change the default install path
> 3. If the issue persists after reinstalling, click the feedback button (top-right corner) to report the issue

---

#### B6: Unknown Startup Error

**Error keys:** `phase_error_unknown`

**What to tell the user:**

> An unexpected error occurred during startup.
>
> 1. Try restarting QoderWork
> 2. If that doesn't help, open **Settings** > **Secure Workspace** tab > click **"Clean Workspace"** and wait for re-download
> 3. If the problem persists, click the feedback button (top-right corner) to report the issue — please include a description of what happened

---

### Category C: Cannot Be Fixed by User

These errors require system upgrades or technical support.

---

#### C1: macOS Version Too Old

**Error keys:** `vf_create_failed`

**What to tell the user:**

> Your macOS version does not support this feature. **macOS 14 (Sonoma) or later** is required.
>
> - If your Mac supports it, upgrade to macOS 14 or later via **System Settings** > **General** > **Software Update**
> - If your Mac hardware does not support macOS 14, this feature unfortunately cannot be used on this machine
> - Click the feedback button (top-right corner) if you need further assistance

---

#### C2: Unrecognized Error

**Condition:** `errorKey` is not in any of the tables above, or `boot-state.json` contains an error not listed here.

**What to tell the user:**

> An unrecognized error occurred. Please report this issue so the team can investigate.

Then open the feedback dialog with context (see Connector Actions below).

---

### Fallback: No Diagnostic File

**Condition:** `~/{{.DataDirName}}/vm/boot-state.json` does not exist or cannot be read.

**What to tell the user:**

> I couldn't find diagnostic information about the error. Let's try some general steps:
>
> 1. Restart QoderWork and try again
> 2. If the problem persists, restart your computer
> 3. If it still doesn't work, open **Settings** > **Secure Workspace** tab > click **"Clean Workspace"**, wait for re-download, and try again
> 4. If none of the above helps, click the feedback button (top-right corner) to report the issue

---

## Connector Actions

Use the QoderWork built-in Connector to help users navigate to relevant UI pages.

### Open VM Settings Page

When you need the user to access the "Clean Workspace" button or check VM status:

```
mcp__qw-builtin__qw_action({ key: "qoderwork.settings.vm", action: "open" })
```

### Open Feedback Dialog

When the user needs to report an issue, pre-fill with diagnostic context:

```
mcp__qw-builtin__qw_action({
  key: "qoderwork.feedback",
  action: "open",
  params: {
    content: "Secure workspace startup error: [brief description of the error]. Error key: [errorKey from boot-state.json]"
  }
})
```

### Check VM Status

To query the current secure workspace status:

```
mcp__qw-builtin__qw_query({ key: "qoderwork.settings.vm" })
```

---

## Important Rules

1. **Never expose internal details.** Do not mention component names like hvkit, VSOCK, HCS, Virtualization.framework, boot-diagnostics, or any internal process names. The user only needs to know about "the secure workspace" or "QoderWork".

2. **Platform awareness.** Check `environment.platform` in boot-state.json:
   - `"darwin"` → macOS instructions (no administrator / PowerShell references)
   - `"windows"` → Windows instructions (administrator, Control Panel, PowerShell)

3. **Match the user's language.** Respond in the same language the user is using (Chinese or English).

4. **Avoid unnecessary alarm.** Frame errors as common, fixable issues. Use reassuring language like "This is usually easy to fix" rather than "critical failure".

5. **Always offer an escalation path.** If the suggested steps don't resolve the issue, always end with: "Click the feedback button in the top-right corner to report this issue for technical support."

6. **Pre-fill feedback when escalating.** When directing users to submit feedback, use the Connector to open the feedback dialog with pre-filled context (error key, platform, brief description) so the support team has the information they need.
