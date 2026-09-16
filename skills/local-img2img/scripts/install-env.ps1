param(
    [string]$venvName = "t2i-tts"
)

Write-Host "正在创建虚拟环境..."
python -m venv $venvName

Write-Host "正在激活虚拟环境..."
& ".\$venvName\Scripts\Activate.ps1"

Write-Host "正在安装依赖..."
pip install -r ..\requirements.txt

Write-Host "环境安装完成!"