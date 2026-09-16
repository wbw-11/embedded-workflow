<#
.SYNOPSIS
	文件锁机制 - 防止并发写入冲突
.DESCRIPTION
	提供简单的文件锁，防止多个脚本同时写入同一文件
.EXAMPLE
	. "$PSScriptRoot\lib\file-lock.ps1"
	$lock = Acquire-FileLock -FilePath 'project_memory.md'
	try {
		# 安全地读写文件
	} finally {
		Release-FileLock -Lock $lock
	}
#>

function Acquire-FileLock {
	param(
		[string]$FilePath,
		[int]$TimeoutSeconds = 10
	)
	
	$lockFile = $FilePath + '.lock'
	$startTime = Get-Date
	
	while ($true) {
		if (-not (Test-Path $lockFile)) {
			# 创建锁文件
			$lockInfo = @{
				PID = $PID
				ProcessName = $MyInvocation.MyCommand.Name
				AcquiredTime = (Get-Date).ToString('o')
			}
			$lockInfo | ConvertTo-Json | Set-Content $lockFile -Encoding UTF8
			return @{ FilePath = $FilePath; LockFile = $lockFile; Acquired = $true }
		}
		
		# 检查锁是否过期（超过30秒自动释放）
		try {
			$lockContent = Get-Content $lockFile -Raw -Encoding UTF8 | ConvertFrom-Json
			$lockTime = [DateTime]::Parse($lockContent.AcquiredTime)
			if (((Get-Date) - $lockTime).TotalSeconds -gt 30) {
				Remove-Item $lockFile -Force
				continue
			}
		} catch {
			Remove-Item $lockFile -Force
			continue
		}
		
		# 检查超时
		if (((Get-Date) - $startTime).TotalSeconds -gt $TimeoutSeconds) {
			Write-Host '[!] 获取文件锁超时' -ForegroundColor Yellow
			return @{ FilePath = $FilePath; LockFile = $lockFile; Acquired = $false }
		}
		
		Start-Sleep -Milliseconds 100
	}
}

function Release-FileLock {
	param($Lock)
	
	if ($Lock -and $Lock.Acquired -and (Test-Path $Lock.LockFile)) {
		Remove-Item $Lock.LockFile -Force -ErrorAction SilentlyContinue
	}
}

Export-ModuleMember -Function Acquire-FileLock, Release-FileLock
