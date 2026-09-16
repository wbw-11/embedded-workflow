<#
.SYNOPSIS
	知识索引工具 - 管理跨项目的知识和踩坑记录
.DESCRIPTION
	从所有项目的 project_memory.md 中提取知识，建立全局索引
.EXAMPLE
	knowledge-index -Index             # 建立索引
	knowledge-index -Search "串口"     # 搜索知识
	knowledge-index -List              # 列出所有索引
	knowledge-index -Report            # 生成知识报告
  version: 1.0.0
#>

param(
	[switch]$Index,
	[string]$Search,
	[switch]$List,
	[switch]$Report
)

$indexFile = Join-Path $env:TEMP 'knowledge_index.json'

function Build-Index {
	try {
				# 候选路径列表（按优先级排序）
		$projectCandidates = @(
			"$env:USERPROFILE\.trae-cn\memory\projects",
			$env:PROJECTS_ROOT,
			"$env:USERPROFILE\Projects",
			"$env:USERPROFILE\Desktop",
			'D:\Projects',
			'D:\MyProject'
		) | Where-Object { $_ -and (Test-Path $_) }
		$projectsDir = $projectCandidates | Select-Object -First 1
		if (-not $projectsDir) {
			$projectsDir = (Get-Location).Path
		}
		Write-Host "  扫描目录: $projectsDir" -ForegroundColor Gray
		
		Write-Host '[1/3] 搜索项目目录...' -ForegroundColor Cyan
		$memoryFiles = Get-ChildItem -Path $projectsDir -Recurse -Filter 'project_memory.md' -File -ErrorAction SilentlyContinue
		Write-Host "  找到 $($memoryFiles.Count) 个 project_memory.md" -ForegroundColor Gray
		
		$index = @{}
		
		foreach ($file in $memoryFiles) {
			$projectName = Split-Path (Split-Path $file.FullName) -Leaf
			Write-Host "[2/3] 处理: $projectName" -ForegroundColor Cyan
			
			try {
				$content = Get-Content $file.FullName -Raw -Encoding UTF8
				
				$sections = @(
					@{ Name = '引脚分配表'; Pattern = '## 引脚分配表[\s\S]*?(?=
## |\Z)' },
					@{ Name = '踩坑记录'; Pattern = '## 踩坑记录[\s\S]*?(?=
## |\Z)' },
					@{ Name = '配置说明'; Pattern = '## 配置说明[\s\S]*?(?=
## |\Z)' },
					@{ Name = '硬件连接'; Pattern = '## 硬件连接[\s\S]*?(?=
## |\Z)' },
					@{ Name = '核心结论'; Pattern = '## Hard Constraints[\s\S]*?(?=
## |\Z)' }
				)
				
				foreach ($section in $sections) {
					$match = [regex]::Match($content, $section.Pattern)
					if ($match.Success) {
						if (-not $index.ContainsKey($section.Name)) {
							$index[$section.Name] = @()
						}
						$index[$section.Name] += @{
							Project = $projectName
							Path = $file.FullName
							Content = $match.Value
						}
					}
				}
			} catch {
				Write-Host "  [!] 读取失败: $($_.Exception.Message)" -ForegroundColor Yellow
			}
		}
		
		$index | ConvertTo-Json -Depth 10 | Set-Content $indexFile -Encoding UTF8
		Write-Host "[3/3] 索引已保存到: $indexFile" -ForegroundColor Green
	} catch {
		Write-Host "[X] 建立索引失败: $($_.Exception.Message)" -ForegroundColor Red
	}
}

function Search-Index {
	param([string]$Query)
	
	try {
		if (-not (Test-Path $indexFile)) {
			Write-Host '[!] 索引不存在，请先执行 knowledge-index -Index' -ForegroundColor Yellow
			return
		}
		
		$index = Get-Content $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
		$found = $false
		
		foreach ($section in $index.PSObject.Properties) {
			foreach ($item in $section.Value) {
				if ($item.Content -match $Query) {
					$found = $true
					Write-Host ''
					Write-Host "项目: $($item.Project)" -ForegroundColor Cyan
					Write-Host "文件: $($item.Path)" -ForegroundColor Gray
					Write-Host '内容:' -ForegroundColor Yellow
					$lines = $item.Content -split "`n"
					for ($i = 0; $i -lt [Math]::Min(10, $lines.Count); $i++) {
						if ($lines[$i] -match $Query) {
							Write-Host "  $($lines[$i])" -ForegroundColor Green
						} else {
							Write-Host "  $($lines[$i])" -ForegroundColor Gray
						}
					}
				}
			}
		}
		
		if (-not $found) {
			Write-Host "[!] 未找到包含 '$Query' 的内容" -ForegroundColor Yellow
		}
	} catch {
		Write-Host "[X] 搜索失败: $($_.Exception.Message)" -ForegroundColor Red
	}
}

function List-Index {
	try {
		if (-not (Test-Path $indexFile)) {
			Write-Host '[!] 索引不存在，请先执行 knowledge-index -Index' -ForegroundColor Yellow
			return
		}
		
		$index = Get-Content $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
		
		$totalProjects = 0
		$allProjects = @{}
		
		foreach ($section in $index.PSObject.Properties) {
			Write-Host "$($section.Name): $($section.Value.Count) 条记录" -ForegroundColor Cyan
			foreach ($item in $section.Value) {
				$allProjects[$item.Project] = $true
				Write-Host "  - $($item.Project)" -ForegroundColor Yellow
			}
		}
		
		$totalProjects = $allProjects.Count
		Write-Host ''
		Write-Host "总计: $totalProjects 个项目已索引" -ForegroundColor Green
	} catch {
		Write-Host "[X] 列出索引失败: $($_.Exception.Message)" -ForegroundColor Red
	}
}

function Generate-Report {
	try {
		if (-not (Test-Path $indexFile)) {
			Write-Host '[!] 索引不存在，请先执行 knowledge-index -Index' -ForegroundColor Yellow
			return
		}
		
		$index = Get-Content $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
		$reportFile = Join-Path (Get-Location).Path 'knowledge_report.md'
		
		$report = "# 知识汇总报告`n`n"
		$report += "生成时间: $(Get-Date)`n`n"
		
		if ($index.'踩坑记录') {
			$report += "## 踩坑记录汇总`n`n"
			foreach ($item in $index.'踩坑记录') {
				$report += "`n### $($item.Project)`n`n$($item.Content)`n"
			}
		}
		
		if ($index.'引脚分配表') {
			$report += "`n## 引脚分配汇总`n`n"
			foreach ($item in $index.'引脚分配表') {
				$report += "`n### $($item.Project)`n`n$($item.Content)`n"
			}
		}
		
		Set-Content $reportFile $report -Encoding UTF8
		Write-Host "[OK] 报告已生成: $reportFile" -ForegroundColor Green
	} catch {
		Write-Host "[X] 生成报告失败: $($_.Exception.Message)" -ForegroundColor Red
	}
}

try {
	if ($Index) {
		Build-Index
	} elseif ($Search) {
		Search-Index -Query $Search
	} elseif ($List) {
		List-Index
	} elseif ($Report) {
		Generate-Report
	} else {
		Write-Host ''
		Write-Host '知识索引工具' -ForegroundColor Cyan
		Write-Host ''
		Write-Host '用法:' -ForegroundColor Yellow
		Write-Host '  knowledge-index -Index             # 建立索引' -ForegroundColor Gray
		Write-Host '  knowledge-index -Search "串口"     # 搜索知识' -ForegroundColor Gray
		Write-Host '  knowledge-index -List              # 列出所有索引' -ForegroundColor Gray
		Write-Host '  knowledge-index -Report            # 生成知识报告' -ForegroundColor Gray
		Write-Host ''
	}
} catch {
	Write-Host "[X] 执行失败: $($_.Exception.Message)" -ForegroundColor Red
	exit 1
}
