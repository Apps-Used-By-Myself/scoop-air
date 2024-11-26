function WriteLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $formattedMessage = "[$timestamp] $Message"

    switch ($Level) {
        'Info' {
            Write-Information -MessageData $formattedMessage -InformationAction Continue
        }
        'Success' {
            Write-Host $formattedMessage -ForegroundColor Green
        }
        'Warning' {
            Write-Warning -Message $formattedMessage
        }
        'Error' {
            Write-Error -Message $formattedMessage -ErrorAction Continue
        }
    }
}

function TestDirectoryEmpty {
    [CmdletBinding()]
    param ([string]$Path)

    $item = Get-Item $Path -Force
    return [string]::IsNullOrEmpty($item.GetFiles("*", [System.IO.SearchOption]::AllDirectories)) -and
    [string]::IsNullOrEmpty($item.GetDirectories("*", [System.IO.SearchOption]::AllDirectories))
}

function EnsureFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    process {
        foreach ($path in $Paths) {
            if (!(Test-Path -Path $path -PathType Leaf)) {
                New-Item -ItemType File -Path $path -Force | Out-Null
            }
        }
    }
}

function EnsureDirectory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    process {
        foreach ($path in $Paths) {
            if (!(Test-Path -Path $path -PathType Container)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }
    }
}

function EnsureSetContent {
    [CmdletBinding()]
    param (
        [string]$FilePath,
        [string]$Content,
        [string]$Encoding = 'UTF8'
    )

    $directory = Split-Path -Path $FilePath -Parent
    EnsureDirectory $directory
    Set-Content -Path $FilePath -Value $Content -Encoding $Encoding -Force
}

function EnsureHardLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Link,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (!(Test-Path $Target -PathType Leaf)) {
        WriteLog "Target is not a file or does not exist: $Target" -Level 'Error'
        return
    }

    $parentDir = Split-Path -Parent $Link
    if (!(Test-Path $parentDir)) {
        EnsureDirectory $parentDir
    }

    if (Test-Path $Link) {
        Remove-Item -Path $Link -Force
    }

    $result = New-Item -ItemType HardLink -Path $Link -Target $Target -Force -ErrorAction Stop

    if ($result) {
        WriteLog "Hard link created: $Link => $Target" -Level 'Info'
    }
}

function RemoveHardLink {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        $fileInfo = Get-Item -Path $Path

        if ($fileInfo.LinkType -eq "HardLink") {
            Remove-Item -Path $Path -Force
        }
    }
}

function EnsureJunction {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Link,

        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    if (!(Test-Path $Target -PathType Container)) {
        WriteLog "Target is not a directory or does not exist: $Target" -Level 'Error'
        return
    }

    $parentDir = Split-Path -Parent $Link
    if (!(Test-Path $parentDir)) {
        EnsureDirectory $parentDir
    }

    if (Test-Path $Link) {
        Remove-Item $Link -Recurse -Force
    }

    $result = New-Item -ItemType Junction -Path $Link -Target $Target -Force -ErrorAction Stop

    if ($result) {
        WriteLog "Junction created: $Link => $Target" -Level 'Info'
    }
}

function RemoveJunction {
    [CmdletBinding()]
    param ([string]$Path)

    if (Test-Path $Path -PathType Container) {
        $item = Get-Item $Path -Force
        if ($item.LinkType -eq "Junction") {
            Remove-Item $Path -Force
        }
    }
}

function RedirectDirectory {
    [CmdletBinding()]
    param (
        [string]$DataDir,
        [string]$PersistDir
    )

    if (Test-Path $DataDir) {
        $item = Get-Item $DataDir -Force
        if ($item.LinkType -and $item.Target -eq $PersistDir) {
            WriteLog """$DataDir"" is already linked to ""$PersistDir""." -Level 'Warning'
            return
        }

        if ($item.LinkType) {
            WriteLog """$DataDir"" is already a link. Exiting script." -Level 'Warning'
            exit
        }
    }

    EnsureDirectory $PersistDir

    if (!(Test-Path $DataDir)) {
        New-Item -ItemType Junction -Path $DataDir -Target $PersistDir | Out-Null
        WriteLog "Junction created: $DataDir => $PersistDir." -Level 'Info'
        return
    }

    $dataEmpty = TestDirectoryEmpty $DataDir
    $persistEmpty = TestDirectoryEmpty $PersistDir

    if (!$dataEmpty -and $persistEmpty) {
        #/E：复制子目录，包括空目录
        # /MOVE：移动文件（复制后删除源）
        # /NFL：不记录文件名
        # /NDL：不记录目录名
        # /NJH：不显示作业头
        # /NJS：不显示作业摘要
        # /NC：不记录文件类别
        # /NS：不记录文件大小
        # /NP：不显示进度百分比
        robocopy $DataDir $PersistDir /E /MOVE /NFL /NDL /NJH /NJS /NC /NS | Out-Null
        WriteLog "Moved contents from ""$DataDir"" to ""$PersistDir""." -Level 'Info'
    }
    elseif (!$dataEmpty -and !$persistEmpty) {
        $backupName = "{0}-backup-{1}" -f $DataDir, (Get-Date -Format "yyMMddHHmmss")
        Rename-Item -Path $DataDir -NewName $backupName
        WriteLog "Both directories contain data. ""$DataDir"" backed up to $backupName." -Level 'Warning'
    }

    if (Test-Path $DataDir) {
        Remove-Item $DataDir -Force -Recurse
    }

    New-Item -ItemType Junction -Path $DataDir -Target $PersistDir | Out-Null
    WriteLog "Junction created: $DataDir => $PersistDir." -Level 'Info'
}


function RemoveDesktopShortcut {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$ShortcutNames
    )

    $desktops = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    )

    foreach ($desktop in $desktops) {
        foreach ($name in $ShortcutNames) {
            $shortcutPath = Join-Path $desktop "$name.lnk"
            if (Test-Path $shortcutPath) {
                Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function RemoveStartMenuItem {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$RelativePaths
    )

    $startMenus = @(
        [System.Environment]::GetFolderPath('CommonStartMenu'),
        [System.Environment]::GetFolderPath('StartMenu')
    ) | ForEach-Object { Join-Path $_ "Programs" }

    foreach ($base in $startMenus) {
        foreach ($path in $RelativePaths) {
            $fullPath = Join-Path $base $path
            if (Test-Path $fullPath) {
                Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function SetEnvVariable {
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Single')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'Single')]
        [string]$Value,

        [Parameter(Mandatory, ParameterSetName = 'Multiple')]
        [hashtable]$Variables
    )

    try {
        function SetSingleVariable {
            param ($VarName, $VarValue)

            $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            if ($isAdmin) {
                [Environment]::SetEnvironmentVariable($VarName, $VarValue, "Machine")
                WriteLog "Added system environment variable: $VarName = $VarValue" Success
            }
            else {
                [Environment]::SetEnvironmentVariable($VarName, $VarValue, "User")
                WriteLog "Added user environment variable: $VarName = $VarValue" Success
            }
        }

        switch ($PSCmdlet.ParameterSetName) {
            'Single' {
                SetSingleVariable -VarName $Name -VarValue $Value
            }
            'Multiple' {
                foreach ($key in $Variables.Keys) {
                    SetSingleVariable -VarName $key -VarValue $Variables[$key]
                }
            }
        }
    }
    catch {
        WriteLog "Failed to set environment variable(s): $_" Error
    }
}


function RemoveEnvVariable {
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Single')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'Multiple')]
        [string[]]$Names
    )

    try {
        function RemoveSingleVariable {
            param ($VarName)

            if ($admin:IsAdmin) {
                $value = [Environment]::GetEnvironmentVariable($VarName, "Machine")
                if ($null -eq $value) {
                    WriteLog "System environment variable not found: $VarName" Warning
                    return
                }

                [Environment]::SetEnvironmentVariable($VarName, $null, "Machine")
                WriteLog "Removed system environment variable: $VarName" Success
            }
            else {
                $value = [Environment]::GetEnvironmentVariable($VarName, "User")
                if ($null -eq $value) {
                    WriteLog "User environment variable not found: $VarName" Warning
                    return
                }

                [Environment]::SetEnvironmentVariable($VarName, $null, "User")
                WriteLog "Removed user environment variable: $VarName" Success
            }
        }

        # 根据参数集处理
        switch ($PSCmdlet.ParameterSetName) {
            'Single' {
                RemoveSingleVariable -VarName $Name
            }
            'Multiple' {
                foreach ($varName in $Names) {
                    RemoveSingleVariable -VarName $varName
                }
            }
        }
    }
    catch {
        WriteLog "Failed to remove environment variable(s): $_" Error
    }
}


Export-ModuleMember -Function WriteLog, TestDirectoryEmpty, EnsureFile, EnsureDirectory, EnsureSetContent, EnsureHardLink, RemoveHardLink, EnsureJunction, RemoveJunction, RedirectDirectory, RemoveDesktopShortcut, RemoveStartMenuItem, SetEnvVariable, RemoveEnvVariable
