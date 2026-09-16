param(
    [string]$venvName = "t2i-tts"
)

& ".\$venvName\Scripts\Activate.ps1"
python server.py