# Only affects display formatting; Get-ChildItem still returns normal file objects.
$global:AuroraFileIcons = @{
    '.gitignore'=@(0xe702,'255;110;40'); '.gitattributes'=@(0xe702,'255;110;40')
    '.gitmodules'=@(0xe702,'255;110;40'); 'azure-pipelines.yml'=@(0xe7b8,'255;110;40')
    'dockerfile'=@(0xf308,'0;220;255'); 'docker-compose.yml'=@(0xf308,'0;220;255')
    '.json'=@(0xe60b,'255;255;0'); '.jsonc'=@(0xe60b,'255;255;0')
    '.yaml'=@(0xe60b,'255;180;0'); '.yml'=@(0xe60b,'255;180;0')
    '.cs'=@(0xe648,'170;130;255'); '.csproj'=@(0xe70c,'255;95;255')
    '.sln'=@(0xe70c,'255;95;255'); '.user'=@(0xe70c,'0;255;255')
    '.xml'=@(0xf121,'160;255;100'); '.config'=@(0xf013,'0;191;255')
    '.md'=@(0xe73e,'0;255;255'); '.txt'=@(0xf15c,'230;230;230')
    '.py'=@(0xe73c,'255;255;0'); '.pyc'=@(0xe73c,'255;180;0')
    '.ps1'=@(0xf489,'0;191;255'); '.psm1'=@(0xf489,'0;191;255')
    '.psd1'=@(0xf489,'0;191;255'); '.bat'=@(0xf17a,'0;255;255')
    '.cmd'=@(0xf17a,'0;255;255'); '.sh'=@(0xf489,'57;255;20')
    '.js'=@(0xe74e,'255;255;0'); '.ts'=@(0xe628,'0;191;255')
    '.jsx'=@(0xe7ba,'0;255;255'); '.tsx'=@(0xe7ba,'0;255;255')
    '.html'=@(0xe736,'255;110;40'); '.css'=@(0xe749,'0;191;255')
    '.zip'=@(0xf410,'255;180;0'); '.7z'=@(0xf410,'255;180;0')
    '.png'=@(0xf03e,'255;95;255'); '.jpg'=@(0xf03e,'255;95;255')
    '.jpeg'=@(0xf03e,'255;95;255'); '.svg'=@(0xf03e,'255;180;0')
    '.mp4'=@(0xf03d,'255;95;255'); '.mp3'=@(0xf001,'0;255;255')
    '.wav'=@(0xf001,'0;255;255'); '.pdf'=@(0xf1c1,'255;80;80')
    '.exe'=@(0xf085,'0;191;255'); '.dll'=@(0xf085,'170;130;255')
}
$global:AuroraFolderIcons = @{
    '.vscode'=@(0xe5fc,'0;191;255'); '.git'=@(0xe5fb,'255;110;40')
    'bin'=@(0xf1b2,'0;255;255'); 'node_modules'=@(0xe718,'57;255;20')
    '.venv'=@(0xe73c,'255;255;0'); 'venv'=@(0xe73c,'255;255;0')
}
function global:Format-AuroraFileName {
    param([System.IO.FileSystemInfo]$Item)
    if ($Item -is [System.IO.DirectoryInfo]) {
        $style=$global:AuroraFolderIcons[$Item.Name]
        if (-not $style) { $style=@(0xf07b,'0;255;255') }
    } else {
        $style=$global:AuroraFileIcons[$Item.Name]
        if (-not $style) { $style=$global:AuroraFileIcons[$Item.Extension] }
        if (-not $style) { $style=@(0xf15b,'57;255;20') }
    }
    "$([char]27)[38;2;$($style[1])m$([char]$style[0]) $($Item.Name)$([char]27)[0m"
}
