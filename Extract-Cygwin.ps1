# Extracts the information of packages from Cygwin setup.ini.
# Copyright(C) 2018 Yoshinori Kawagita

# The help information of this script

<#
.SYNOPSIS
    Extracts the information of Cygwin packages from setup.ini.

.DESCRIPTION
    This script enumerates the PSObject containing Cygwin package's information extracted from
    setup.ini on x86 or x86_64 directory to the pipeline.

.PARAMETER Arch
    Specifies x86 or x86_64 as the architecture for which Cygwin setup.ini is described.

.PARAMETER Category
    Targets Cygwin packages included in the specified category.

.PARAMETER Country
    Selects the mirror site at random if present in the specified country with -Download.

.PARAMETER Download
    Downloads Cygwin installer, setup.ini, and packages whose state are 'New' or 'Updated'.

.PARAMETER LocalPackageDirectory
    Reads the version of Cygwin packages which have already been installed to the specified path
    on the local. If this parameter is not specified, the state of all packages is always 'New'.

.PARAMETER Mirror
    Sets the mirror site to the specified URL with -Download.

.PARAMETER Package
    Targets Cygwin packages of the specified name.

.PARAMETER Quiet
    Quiets for extracting or downloading Cygwin packages.

.PARAMETER Regex
    Targets Cygwin packages whose name matchs the specified regular expression.

.PARAMETER Requires
    Targets Cygwin packages required by other packages.

.PARAMETER Root
    Sets the root of x86 or x86_64 directory on the local to the specified path.

.PARAMETER Software
    Targets Cygwin packages included in the specified software.

.LINK
    Cygwin website: http://cygwin.com/
    Mirror list:    http://cygwin.com/mirrors.html

.EXAMPLE
    C:\PS> .\Extract-Cygwin.ps1 x86 -Package cygwin

    Description : The UNIX emulation engine
    Hash        : 4a95a1fbaff0b9ca767a331905f5afe5188b00e4ba4995cab36a6150bb0ca868
                  cd5e6f4af486a2649d2cd10904469fc426e305b4580b0fcfea5f79151ec219d0
    Path        : x86/release/cygwin/cygwin-2.8.0-1.tar.xz
    Version     : 2.8.0-1
    Requires    : base-cygwin
    Category    : Base
    Size        : 1955564
    Name        : cygwin
#>

# Parametes of this script

param(
    [parameter(Mandatory=$true)]
    [ValidateSet('x86', 'x86_64')]
    [string]$Arch,
    [string[]]$Category=@(),
    [string]$Country="",
    [switch]$Download,
    [string]$LocalPackageDirectory="",
    [string]$Mirror="",
    [string[]]$Package=@(),
    [switch]$Quiet,
    [string[]]$Regex=@(),
    [switch]$Requires,
    [string]$Root="",
    [string[]]$Software=@()
)

#$PROG_PATH = $MyInvocation.MyCommand.Path -replace '\\', '/' -replace '/[^/]+$', '/';
#$PROG_GET_MIRROR = $PROG_PATH + 'Get-CygwinMirror.ps1';
#$PROG_CHECK_PACKAGE = $PROG_PATH + 'Check-Cygwin.ps1';

# The path of Cygwin installed database

$CYGWIN_INSTALLED_DATABASE = '/etc/setup/installed.db';
$CYGWIN_INSTALLED_PACKAGE_SUFFIX_EXPR = '\.tar\.[a-z0-9]+$';

# Parameters of the version object

$CYGWIN_VERSION_NUMBER = 'Version';
$CYGWIN_VERSION_DATE = 'Date';

# The size of digits in a version, separated by '.'

$CYGWIN_VERSION_DIGIT_SIZE = 5;

# The index of development information in a version, separated by '.'

$CYGWIN_VERSION_DEVEL_STAGE_INDEX = $CYGWIN_VERSION_DIGIT_SIZE;
$CYGWIN_VERSION_DEVEL_VERSION_INDEX = $CYGWIN_VERSION_DEVEL_STAGE_INDEX + 1;

# The map of the develpment name to ordinal numbers

$CYGWIN_VERSION_DEVEL_ORDERED_MAP = @{
    'alpha' = -5;
    'beta' = -4;
    'pr' = -4;
    'pre' = -4;
    'devel' = -3;
    'rc' = -2;
    'ga' = -1;
};

# Compares the specified two version objects.
#
# $VersionObject1   the version object
# $VersionObject2   the version object
# return -1, 0, or 1 if 1st object is less than, equal to, or greater than 2nd

function CompareCygwinVersion(
    [parameter(Mandatory=$true)][Object]$VersionObject1,
    [parameter(Mandatory=$true)][Object]$VersionObject2) {

    # Compares the date in the version object

    $date1 = $VersionObject1.($CYGWIN_VERSION_DATE);
    $date2 = $VersionObject2.($CYGWIN_VERSION_DATE);
    if (($date1 -ne $null) -and ($date2 -ne $null)) {
        return [Math]::Sign([int]$date1 - [int]$date2);
    }

    # Compares the value in the array of version numbers

    $versions1 = $VersionObject1.($CYGWIN_VERSION_NUMBER);
    $versions2 = $VersionObject2.($CYGWIN_VERSION_NUMBER);
    $vercount = $versions1.Count;
    if ($vercount -gt $versions2.Count) {
        $vercount = $versions2.Count;
    }

    for ($i = 0; $i -lt $vercount; $i++) {
        $numbers1 = $versions1.Item($i);
        $numbers2 = $versions2.Item($i);

        for ($j = 0; $j -lt $CYGWIN_VERSION_DIGIT_SIZE; $j++) {
            $numdiff = $numbers1[$j] - $numbers2[$j];
            if ($numdiff -ne 0) {  # Different version number
                return [Math]::Sign($numdiff);
            }
        }

        $develstage1 = $numbers1[$CYGWIN_VERSION_DEVEL_STAGE_INDEX];
        $develstage2 = $numbers2[$CYGWIN_VERSION_DEVEL_STAGE_INDEX];
        $develdiff = $CYGWIN_VERSION_DEVEL_ORDERED_MAP.Item($develstage1) `
                      - $CYGWIN_VERSION_DEVEL_ORDERED_MAP.Item($develstage2);
        if ($develdiff -eq 0) {  # Same development stage
            $develdiff = $develstage1.compareTo($develstage2);
            if ($develdiff -eq 0) {  # Same alphabet development stage
                $develdiff = [double]$numbers1[$CYGWIN_VERSION_DEVEL_VERSION_INDEX] `
                              - [double]$numbers2[$CYGWIN_VERSION_DEVEL_VERSION_INDEX];
            }
        }

        if ($develdiff -ne 0) {  # Different development information
            return [Math]::Sign($develdiff);
        }
    }

    return $versions1.Count - $versions2.Count;
}

# The regular expression of version date

$CYGWIN_VERSION_DATE_DELIM_EXPR = '[-.]';
$CYGWIN_VERSION_DATE_REGEX = [Regex]('\.?(20[0-9]{2}' `
                                    + $CYGWIN_VERSION_DATE_DELIM_EXPR + '?(0[1-9]|1[0-2])' `
                                    + $CYGWIN_VERSION_DATE_DELIM_EXPR + '?[0-3][0-9])');

# The regular expression of version control

$CYGWIN_VERSION_CONTROL_HEX_MIN_LENGTH = 7;
$CYGWIN_VERSION_CONTROL_HEX_MAX_LENGTH = 8;
$CYGWIN_VERSION_CONTROL_HEX_REGEX = [Regex]('^\.?([0-9a-f]{' `
                                            + $CYGWIN_VERSION_CONTROL_HEX_MIN_LENGTH `
                                            + ',})');
$CYGWIN_VERSION_CONTROL_REGEX = [Regex]('\.?(git|bzr|cvs|darcs|deb|hg|rcgit|rcs|svn)[.0-9a-f]*');

# The regular expression of version digit

$CYGWIN_VERSION_DIGIT_REGEX = [Regex]('^\.?([0-9]+)');

# The regular expression of development version

$CYGWIN_VERSION_DEVEL_REGEX = [Regex]('^[-+.]?([A-Za-z]+)([0-9]*(\.[0-9]+)?)');

# The regular expression of version separator

$CYGWIN_VERSION_SEPARATOR_REGEX = [Regex]('^.');

# Returns the version object for the specified string.
#
# $VersionString  the version string

function GetCygwinVersion([parameter(Mandatory=$true)][string]$VersionString) {
    $verstr = $VersionString.Trim();
    $verobj = New-Object PSObject -Prop @{
        $CYGWIN_VERSION_NUMBER = New-Object System.Collections.ArrayList;
    };

    # Removes the version date and control information from the specified string

    $match = $CYGWIN_VERSION_DATE_REGEX.Match($verstr);
    if ($match.Success) {
        $date = $match.Groups[1].Value -replace $CYGWIN_VERSION_DATE_DELIM_EXPR, "";
        $verobj | Add-Member NoteProperty $CYGWIN_VERSION_DATE $date;
        $verstr = $verstr.Substring(0, $match.Index) `
                   + $verstr.Substring($match.Index + $match.Length);
    }
    $match = $CYGWIN_VERSION_CONTROL_REGEX.Match($verstr);
    if ($match.Success) {
        $verstr = $verstr.Substring(0, $match.Index) `
                   + $verstr.Substring($match.Index + $match.Length);
    }

    # Reads version digits and/or development information from the specified string

    $verlist = $verobj.($CYGWIN_VERSION_NUMBER);
    $verinit = $true;
    while ($verstr -ne "") {
        if ($verinit) {
            $verinit = $false;
            $vercount = 0;
            $verarray = @();
            for ($i = 0; $i -lt $CYGWIN_VERSION_DIGIT_SIZE; $i++) {
                $verarray += 0;
            }
            $verarray += "";
            $verarray += "";
            [void]$verlist.Add($verarray);
        }
        $match = $CYGWIN_VERSION_CONTROL_HEX_REGEX.Match($verstr);
        $verbase = 16;
        if ((-not $match.Success) `
            -or ($match.Groups[1].Length -gt $CYGWIN_VERSION_CONTROL_HEX_MAX_LENGTH)) {
            $match = $CYGWIN_VERSION_DIGIT_REGEX.Match($verstr);
            $verbase = 10;
        }
        if ($match.Success) {  # Version digits separated by '.'
            if ($vercount -lt $CYGWIN_VERSION_DIGIT_SIZE) {
                $verarray[$vercount] = [System.Convert]::ToInt32($match.Groups[1].Value, $verbase);
                $vercount++;
            }
        } else {
            $match = $CYGWIN_VERSION_DEVEL_REGEX.Match($verstr);
            if ($match.Success) {  # Development version
                if ($verarray[$CYGWIN_VERSION_DEVEL_STAGE_INDEX] -eq "") {
                    $verarray[$CYGWIN_VERSION_DEVEL_STAGE_INDEX] = $match.Groups[1].Value;
                    $verarray[$CYGWIN_VERSION_DEVEL_VERSION_INDEX] = $match.Groups[2].Value;
                }
            } else {  # Another character as a separator
                if ($vercount -gt 0) {
                    $verinit = $true;
                }
                $match = $CYGWIN_VERSION_SEPARATOR_REGEX.Match($verstr);
            }
        }
        $verstr = $verstr.Substring($match.Length);
    }

    return $verobj;
}

# The cygwin website URL

$CYGWIN_WEBSITE = 'http://cygwin.com/';

# The cygwin mirror list

$CYGWIN_MIRROR_LIST = $CYGWIN_WEBSITE + 'mirrors.lst';

# Fields of the information extracted from setup.ini

$FIELD_CATEGORY = 'Category';
$FIELD_DESCRIPTION = 'Description';
$FIELD_DATE = 'Date';
$FIELD_HASH = 'Hash';
$FIELD_NAME = 'Name';
$FIELD_PATH = 'Path';
$FIELD_REQUIRES = 'Requires';
$FIELD_SIZE = 'Size';
$FIELD_STATE = 'State';
$FIELD_URL = 'URL';
$FIELD_VERSION = 'Version';

$FIELD_PATH_REGEX = [Regex]('(.*/)?([-+.0-9a-zA-Z_]+)$');

# The state of package's file on the mirror

$STATE_UNDEFINED = 'Undefined';
$STATE_NEW = 'New';
$STATE_UPDATED = 'Updated';
$STATE_OLDER = 'Older';
$STATE_NOT_FOUND = 'Not Found';
$STATE_ERROR = 'Error';

# Returns the Cygwin mirror site for the specified country.
#
# $country  a country name

function GetCygwinMirror([string]$country) {
    if ($country -eq "") {
        $country = ([System.Globalization.RegionInfo]::CurrentRegion).EnglishName;
    }
    if ($country.StartsWith('Hong Kong')) {
        $country = 'Hong Kong';
    } elseif ($country -eq 'United Kingdom') {
        $country = 'UK';
    }
    $response = $null;
    $stream = $null;
    $mirrorlist = New-Object System.Collections.ArrayList 32;

    try {
        $request = [System.Net.WebRequest]::Create($CYGWIN_MIRROR_LIST);
        $request.KeepAlive = $false;
        $response = $request.GetResponse();
        $stream = $response.GetResponseStream();
        $reader = New-Object System.IO.StreamReader $stream;
        while ($reader.Peek() -ge 0) {
            $field = $reader.ReadLine().Split(';');

            # Adds the mirror site of only the target country to the list

            if (($country -eq $field[2]) -or ($country -eq $field[3])) {
                [void]$mirrorlist.Add($field[0]);
            }
        }
    } catch [System.Net.WebException] {
        $exception = $_.Exception;
        if ($exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            Write-Error "'$CYGWIN_MIRROR_LIST' is not found" -Category InvalidArgument;
        } else {
            Write-Error -Exception $exception;
        }
        exit 1;
    } finally {
        if ($reader -ne $null) {
            $reader.Close();
        }
        if ($stream -ne $null) {
            $stream.Close();
        }
        if ($response -ne $null) {
            $response.Close();
        }
    }

    if ($mirrorlist.Count -gt 0) {
        $mirrorlist.Item((Get-Random -Minimum 0 -Maximum ($mirrorlist.Count - 1)));
    }
}

# Downloads the file for the specified package from the mirror site.
#
# $PackageObject  the object of a package
# $DownloadParam  the object of download parameters

function DownloadCygwinPackage([Object]$PackageObject, [Object]$DownloadParam) {
    $response = $null;
    $stream = $null;
    $writer = $null;
    $url = $PackageObject.($FIELD_URL);
    $state = $PackageObject.($FIELD_STATE);
    $size = 0L;
    $date = $null;
    $filematch = $FIELD_PATH_REGEX.Match($PackageObject.($FIELD_PATH));
    $filepath = $DownloadParam.Root + $PackageObject.($FIELD_PATH);
    $fileparent = $DownloadParam.Root + $filematch.Groups[1].Value;
    $dlfile = $filematch.Groups[2].Value;
    $dlpath = $env:TEMP + '\\' + $dlfile;

    try {

        # Gets the timestamp and http response of downloaded file

        $response = GetResponse $url ([System.Net.WebRequestMethods+Ftp]::GetDateTimestamp);
        $date = $response.LastModified;

        if ($url.StartsWith('ftp://')) {
            $response.Close();
            $response = GetResponse $url ([System.Net.WebRequestMethods+Ftp]::GetFileSize);
            $size = $response.ContentLength;
            $response.Close();
            $response = $null;
        } else {
            $size = $response.ContentLength;
        }

        if (($state -eq $STATE_UNDEFINED) `
            -or $PackageObject.($FIELD_SIZE).Equals($size)) {
            if ($state -eq $STATE_UNDEFINED) {  # Cygwin installer or setup.ini
                $state = $STATE_UPDATED;
            } elseif (($state -ne $STATE_NEW) `
                      -and ($state -ne $STATE_UPDATED)) {  # Older or the same version
                return;
            }

            # Never downloads the file if the same is present and new on the local

            $fileobj = Get-Item $filepath 2> $null;
            if (($fileobj -ne $null) `
                -and ($fileobj.LastWriteTime.CompareTo($date) -ge 0)) {
                return;
            }

            if ($response -eq $null) {
                $response = GetResponse $url ([System.Net.WebRequestMethods+Ftp]::DownloadFile);
            }

            # Writes downloaded data to the temporary file from http response

            $writer = New-Object System.IO.FileStream $dlpath, `
                                                      ([System.IO.FileMode]::Create), `
                                                      ([System.IO.FileAccess]::Write);
            $stream = $response.GetResponseStream();

            if ($DownloadParam.Verbose) {
                $DownloadParam.Progress.Start($dlfile, $response.ContentLength, $true);
            }
            $length = $stream.Read($DownloadParam.Buffer, 0, $DownloadParam.Buffer.Length);
            if ($length -gt 0) {
                do {
                    if ($DownloadParam.Verbose) {
                        $DownloadParam.Progress.Increse($length);
                        $DownloadParam.Progress.Show();
                    }
                    $writer.Write($DownloadParam.Buffer, 0, $length);
                    $length = $stream.Read($DownloadParam.Buffer, 0, $DownloadParam.Buffer.Length);
                } while ($length -gt 0);
            }
            if ($DownloadParam.Verbose) {
                $DownloadParam.Progress.End();
            }
        } else {  # The size different from the information in setup.ini
            $state = $STATE_ERROR;
        }
    } catch [System.Net.WebException] {
        if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound) {
            throw;
        }
        $state = $STATE_NOT_FOUND;
    } finally {
        if ($stream -ne $null) {
            $stream.Close();
            $stream = $null;
        }
        if ($response -ne $null) {
            $response.Close();
        }
        if ($writer -ne $null) {
            $writer.Flush();
            $writer.Close();

            $dlobj = Get-Item $dlpath 2> $null;
            try {
                if ($dlobj.Length -eq $size) {
                    $dlhash = "";
                    $dlcheck = $true;

                    if ($PackageObject.($FIELD_HASH) -ne "") {
                        $provider = $DownloadParam.CryptoServiceProvider;
                        $stream = $dlobj.OpenRead();
                        try {
                            $str = [System.BitConverter]::ToString($provider.ComputeHash($stream));
                            $dlhash = $str.Replace('-', "").ToLower();
                        } finally {
                            $stream.Close();
                        }
                        $dlcheck = $PackageObject.($FIELD_HASH).Equals($dlhash);
                    }

                    if ($dlcheck) {

                        # Sets the timestamp on the mirror into the temporary file
                        # and moves it to the path of package parameters

                        $dlobj.LastWriteTime = $date;

                        if ($fileparent.Length -gt 0) {
                            New-Item $fileparent -ItemType Directory -Force > $null 2>&1;
                        }

                        Move-Item $dlpath $filepath -Force;
                        if (-not $?) {
                            exit 1;
                        }
                    } else {  # The hash value different from the information in setup.ini
                        $state = $STATE_ERROR;
                    }
                }
#                else {
#                    # Throws the exception of writng or downloading the package's file
#                }
            } finally {
                Remove-Item $dlpath 2> $null;
            }
        }

        $PackageObject.($FIELD_STATE) = $state;
        $PackageObject.($FIELD_DATE) = $date;
    }
}

# Returns the HTTP or FTP reqponse for the specified URL.
#
# $URL     the request URL
# $Method  the request method

function GetResponse([string]$URL, [string]$Method="") {
    $request = [System.Net.WebRequest]::Create($URL);
    $request.KeepAlive = $false;
    if ($url.StartsWith('ftp://')) {
        $request.Method = $Method;
    }
    return $request.GetResponse();
}


# The file or directory names of setup.exe and setup.ini

$SETUP_X64_ARCH = 'x86_64';
$SETUP_X64_ROOT = $SETUP_X64_ARCH + '/';
$SETUP_X64_PACKAGE_ROOT = $SETUP_X64_ROOT + 'release/';
$SETUP_X64_EXE_FILE = 'setup-x86_64.exe';
$SETUP_X86_ARCH = 'x86';
$SETUP_X86_ROOT = $SETUP_X86_ARCH + '/';
$SETUP_X86_PACKAGE_ROOT = $SETUP_X86_ROOT + 'release/';
$SETUP_X86_EXE_FILE = 'setup-x86.exe';
$SETUP_NOARCH_PACKAGE_ROOT = 'noarch/release/';
$SETUP_EXE_NAME = 'Setup.exe';
$SETUP_INI_NAME = 'Setup.ini';
$SETUP_INI_FILE = 'setup.ini';

# Sets the object of setup files on 'x86' or 'x86_64' directory
# before targeted packages

$SetupArch = $Arch;
$SetupExe = New-Object PSObject -Prop @{
    $FIELD_CATEGORY = "";
    $FIELD_DATE = $null;
    $FIELD_DESCRIPTION = "";
    $FIELD_HASH = "";
    $FIELD_NAME = $SETUP_EXE_NAME;
    $FIELD_PATH = "";
    $FIELD_REQUIRES = "";
    $FIELD_SIZE = 0L;
    $FIELD_STATE = $STATE_UNDEFINED;
    $FIELD_VERSION = "";
    $FIELD_URL = "";
};
$SetupIni = New-Object PSObject -Prop @{
    $FIELD_CATEGORY = "";
    $FIELD_DATE = $null;
    $FIELD_DESCRIPTION = "";
    $FIELD_HASH = "";
    $FIELD_NAME = $SETUP_INI_NAME;
    $FIELD_PATH = "";
    $FIELD_REQUIRES = "";
    $FIELD_SIZE = 0L;
    $FIELD_STATE = $STATE_UNDEFINED;
    $FIELD_VERSION = "";
    $FIELD_URL = "";
};
$SetupRoot = $Root -replace '\\', '/' -replace '[^/]$', '$&/';

switch ($SetupArch) {
    $SETUP_X86_ARCH {
        $SetupExe.($FIELD_PATH) = $SETUP_X86_EXE_FILE;
        $SetupExe.($FIELD_URL) = $CYGWIN_WEBSITE + $SETUP_X86_EXE_FILE;
        $SetupIni.($FIELD_PATH) = $SETUP_X86_ROOT + $SETUP_INI_FILE;
        $PackageRoot = $SetupRoot + $SETUP_X86_PACKAGE_ROOT;
    }
    $SETUP_X64_ARCH {
        $SetupExe.($FIELD_PATH) = $SETUP_X64_EXE_FILE;
        $SetupExe.($FIELD_URL) = $CYGWIN_WEBSITE + $SETUP_X64_EXE_FILE;
        $SetupIni.($FIELD_PATH) = $SETUP_X64_ROOT + $SETUP_INI_FILE;
        $PackageRoot = $SetupRoot + $SETUP_X64_PACKAGE_ROOT;
    }
}
$PackageLocalDirectory = $LocalPackageDirectory -replace '\\', '/' -replace '/$', "";
$PackageMap = @{};
$PackageInstalledMap = $null;
$Verbose = -not $Quiet.IsPresent;

# The progress of extracting or downloading package

$ProgressLimit = `
if ([Console]::BufferWidth -le 60) {
    [Console]::BufferWidth - 10;
} else {
    50;
};
$Progress = New-Object PSObject -Prop @{
    'FileName' = "";
    'FileSize' = 0;
    'ByteLength' = 0;
    'Percent' = 0;
    'Limit' = $ProgressLimit;
    'Count' = 0;
    'CountRate' = 0.0;
    'CountBuffer' = New-Object System.Text.StringBuilder ($ProgressLimit + 8);
    'ConsoleCursorVisible' = [Console]::CursorVisible;
} `
| Add-Member -PassThru ScriptMethod 'Start' {
    $this.FileName = $args[0];
    $this.FileSize = $args[1];
    $this.ByteLength = 0;
    $this.Percent = -1;
    $this.Count = 0;
    $this.CountRate = 100 / $this.Limit;
    $this.CountBuffer.Length = 0;
    [void]$this.CountBuffer.Append(' [>').Append(' ', $this.Limit - 1).Append('] ');
    if ($args[2]) {
        $format = 'Downloading {0}';
    } else {
        $format = 'Extracting the information from {0}';
    }
    $message = [String]::Format($format, $this.FileName);
    if ($message.Length -ge [Console]::BufferWidth) {
        $message = $message.Substring(0, [Console]::BufferWidth - 1);
    }
    [Console]::Error.WriteLine($message + "`n");
    [Console]::CursorVisible = $false;
} `
| Add-Member -PassThru ScriptMethod 'Increse' {
    $this.ByteLength += $args[0];
} `
| Add-Member -PassThru ScriptMethod 'Show' {
    $percent = [Math]::Floor($this.ByteLength / $this.FileSize * 100);
    if ($this.Percent -lt $percent) {
        $this.Percent = $percent;
        $count = [Math]::Floor($percent / $this.CountRate);
        if (($this.Count -lt $count) -and ($this.Limit -gt $count)) {
            $this.Count = $count;
            $this.CountBuffer.Length = $count + 1;
            [void]$this.CountBuffer.Append('=>').Append(' ', $this.Limit - $count - 1).Append('] ');
        } else {
            $this.CountBuffer.Length = $this.Limit + 4;
        }
        [Console]::Error.Write($this.CountBuffer.Append($percent).Append('%').ToString());
        [Console]::CursorLeft = 0;
    }
} `
| Add-Member -PassThru ScriptMethod 'End' {
    [Console]::Error.Write(' ' * $this.CountBuffer.Capacity);
    [Console]::CursorTop -= 2;
    [Console]::CursorLeft = 0;
    [Console]::Error.Write(' ' * ([Console]::BufferWidth - 1));
    [Console]::CursorLeft = 0;
    [Console]::CursorVisible = $true;
};

# The object of download parameters

$DownloadParam = New-Object PSObject -Prop @{
    'Root' = $SetupRoot;
    'Progress' = $Progress;
    'Buffer' = $null;
    'CryptoServiceProvider' = $null;
    'Verbose' = $Verbose;
};

# The list of targeted packages

$TargetedCategoryList = New-Object System.Collections.ArrayList 16;
$TargetedSoftwareList = New-Object System.Collections.ArrayList 16;
$TargetedRegexList = New-Object System.Collections.ArrayList 16;
$TargetedPackageList = New-Object System.Collections.ArrayList 256;

$Category | `
ForEach-Object {
    $name = $_.Substring(0, 1).ToUpper() + $_.Substring(1).ToLower();
    if (($name -ne "") `
        -and (-not $TargetedCategoryList.Contains($name))) {
        [void]$TargetedCategoryList.Add($name);
    }
}
$Software | `
ForEach-Object {
    if (($_ -ne "") `
        -and (-not $TargetedSoftwareList.Contains($_))) {
        [void]$TargetedSoftwareList.Add($_);
    }
}
$Regex | `
ForEach-Object {
    [void]$TargetedRegexList.Add([Regex]($_));
    if (-not $?) {
        exit 1;
    }
}
$Package | `
ForEach-Object {
    if (-not $TargetedPackageList.Contains($_)) {
        [void]$TargetedPackageList.Add($_);
    }
}


$ConsoleCursorVisible = [Console]::CursorVisible;
$SystemDir = [System.IO.Directory]::GetCurrentDirectory();
[System.IO.Directory]::SetCurrentDirectory((Get-Location).Path);
[Console]::CursorVisible = $true;

$response = $null;
$reader = $null;
try {

#[Console]::Error.Write('Package Directory: ' + $PackageLocalDirectory + "`n");
    if ($PackageLocalDirectory -ne "") {
#            Import-Module $PROG_CHECK_PACKAGE 2> $null;
        $PackageInstalledMap = New-Object Hashtable 256;
        $fileobj = Get-Item ($PackageLocalDirectory + $CYGWIN_INSTALLED_DATABASE) 2> $null;
        if ($?) {
            $reader = $null;
            try {
                # Read the package's name and file from Cygwin installed.db

                $reader = $fileobj.OpenText();
                [void]$reader.ReadLine();  # Ignore "INSTALLED.DB x"

                if ($reader.Peek() -ge 0) {
                    do {
                        $field = $reader.ReadLine().Split(' ');
                        $name = $field[0];
                        $verstr = $field[1].Substring($name.Length + 1) `
                                   -replace $CYGWIN_INSTALLED_PACKAGE_SUFFIX_EXPR, "";
#[Console]::Error.Write($name + ': ' + $verstr + "`n");
                        $PackageInstalledMap.Add($name, (GetCygwinVersion $verstr));
                    } while ($reader.Peek() -ge 0);
                }
            } finally {
                if ($reader -ne $null) {
                    $reader.Close();
                }
            }
        }
    }

    # Checks the timestamp of setup-x86.exe or setup-x86_64.exe in Cygwin site
    # and setup.ini from the specified mirror, and download its if specified

    if ($Download.IsPresent) {
        if ($Mirror -eq "") {
#            Import-Module $PROG_GET_MIRROR 2> $null;;
            $Mirror = GetCygwinMirror $Country;
            if ($Mirror -eq $null) {
                Write-Error "Mirror must be specified" -Category SyntaxError;
                exit 1;
            }
        } else {
            $Mirror = $Mirror -replace '\\', '/' -replace '[^/]$', '$&/';
        }
        $response = GetResponse $Mirror ([System.Net.WebRequestMethods+Ftp]::ListDirectory);
        $SetupIni.($FIELD_URL) = $Mirror + $SetupIni.($FIELD_PATH);
        $DownloadParam.Buffer = New-Object byte[] 10240;
        $DownloadParam.CryptoServiceProvider = `
            New-Object System.Security.Cryptography.SHA512CryptoServiceProvider;

        DownloadCygwinPackage $SetupExe $DownloadParam;
        DownloadCygwinPackage $SetupIni $DownloadParam;
    }

    if (($TargetedCategoryList.Count -eq 0) `
        -and ($TargetedSoftwareList.Count -eq 0) `
        -and ($TargetedRegexList.Count -eq 0) `
        -and ($TargetedPackageList.Count -eq 0)) {
        exit 0;
    }

    # Reads the information of all packages from setup.ini and create the object
    # of it whose name is appended to the targeted list if specified by options

    $fileobj = Get-Item ($SetupRoot + $SetupIni.($FIELD_PATH));
    if (-not $?) {
        exit 1;
    }

    if ($Verbose) {
        $Progress.Start($SetupIni.($FIELD_PATH), $fileobj.Length, $false);
    }

    $reader = $fileobj.OpenText();
    $packname = "";
    $packobj = @{
        $FIELD_CATEGORY = "";
        $FIELD_DESCRIPTION = "";
        $FIELD_HASH = "";
        $FIELD_PATH = "";
        $FIELD_REQUIRES = "";
        $FIELD_SIZE = 0L;
        $FIELD_STATE = "";
        $FIELD_VERSION = "";
    };
    $packregex = `
        [Regex]('(.*/release/([-+.0-9a-zA-Z_]+)/([-+.0-9a-zA-Z_]+/)?[-+.0-9a-zA-Z_]+) ([0-9]+) ([0-9a-f]+)$');
    $targetable = $false;
    $targeted = $false;
    $lastest = $true;

    if ($reader.Peek() -ge 0) {
        do {
            $text = $reader.ReadLine();
            if ($text.StartsWith('@ ')) {  # "@ xxx"
                if ($Verbose) {
                    $Progress.Show();
                }

                # Creates the object of a package and map the name to it

                $packname = $text.Substring(2);
                $packobj = New-Object PSObject -Prop @{
                    $FIELD_CATEGORY = "";
                    $FIELD_DESCRIPTION = "";
                    $FIELD_HASH = "";
                    $FIELD_PATH = "";
                    $FIELD_REQUIRES = "";
                    $FIELD_SIZE = 0L;
                    $FIELD_STATE = $STATE_NEW;
                    $FIELD_VERSION = "";
                };
                $PackageMap.Add($packname, $packobj);

                $targetable = $false;
                $targeted = $TargetedPackageList.Contains($packname);
                if (-not $targeted) {
                    $targetable = $true;
                    for ($i = 0; $i -lt $TargetedRegexList.Count; $i++) {
                        if ($TargetedRegexList.Item($i).IsMatch($packname)) {
                            [void]$TargetedPackageList.Add($packname);
                            $targetable = $false;
                            $targeted = $true;
                            break;
                        }
                    }
                }
                $lastest = $true;
            } elseif ($text.StartsWith('[')) {  # "[prev]" or "[test]"
                $lastest = $false;
            } elseif ($lastest -and ($text.IndexOf('::') -lt 0)) {

                # Reads the name and value separated by a colon

                $index = $text.IndexOf(':');
                if ($index -ge 0) {
                    $name = $text.Substring(0, $index);
                    $value = $text.Substring($index + 1).Trim();

                    switch ($name) {
                        'arch' {  # "arch: x86" or "arch: x86_64"
                            if ($SetupArch -ne $value) {
                                $Progress.End();
                                Write-Error "incorrect ${SetupArch}/setup.ini" -Category InvalidData;
                                exit 1;
                            }
                        }
                        'setup-version' {  # "setup-version: xxx"
                            $SetupExe.($FIELD_VERSION) = $value;
                        }
                        'sdesc' {  # "sdesc: \"xxx\""
                            $packobj.($FIELD_DESCRIPTION) = $value.Trim(' "');
                        }
                        'install' {  # "install: x86(_64)?/release/xxx/(yyy/)?zzz.(bz2|xz) .*"
                            $match = $packregex.Match($value);
                            if ($match.Success) {
                                if ($targetable `
                                    -and $TargetedSoftwareList.Contains($match.Groups[2].Value)) {
                                    [void]$TargetedPackageList.Add($packname);
                                    $targetable = $false;
                                    $targeted = $true;
                                }
                                $packobj.($FIELD_PATH) = $match.Groups[1].Value;
                                $packobj.($FIELD_SIZE) = [long]::Parse($match.Groups[4].Value);
                                $packobj.($FIELD_HASH) = $match.Groups[5].Value;
                            }
                        }
                        'requires' {  # "requires: xxx yyy zzz"
                            $list = $value.Split(' ');
                            if ($targeted -and $Requires.IsPresent) {
                                $list `
                                | ForEach-Object {
                                    if (-not $TargetedPackageList.Contains($_)) {
                                        [void]$TargetedPackageList.Add($_);
                                    }
                                }
                            }
                            $packobj.($FIELD_REQUIRES) = $value;
                        }
                        'category' {  # "category: xxx yyy zzz"
                            $list = $value.Split(' ');
                            if ($targetable) {
                                for ($i = 0; $i -lt $list.Length; $i++) {
                                    if ($TargetedCategoryList.Contains($list[$i])) {
                                        [void]$TargetedPackageList.Add($packname);
                                        $targetable = $false;
                                        $targeted = $true;
                                        break;
                                    }
                                }
                            }
                            $packobj.($FIELD_CATEGORY) = $value;
                        }
                        'version' {  # "version: xxx"
                            $packobj.($FIELD_VERSION) = $value;
                        }
                    }
                }
            }
            $Progress.Increse($text.Length + 1);
        } while ($reader.Peek() -ge 0);
    }

    if ($Verbose) {
        $Progress.End();
    }

    if ($Requires.IsPresent) {
        $count = $TargetedPackageList.Count;
        $index = 0;
        $targetedcount = 0;
        do {
            $count += $targetedcount;
            $targetedcount = 0;
            do {
                $packobj = $PackageMap.Item($TargetedPackageList.Item($index));
                if ($packobj -ne $null) {
                    $value = $packobj.($FIELD_REQUIRES);

                    if ($value -ne "") {
                        $list = $value.Split(' ');

                        # Appends the package required by and described before a targeted package
                        # in setup.ini to the targeted list

                        for ($i = 0; $i -lt $list.Length; $i++) {
                            if (-not $TargetedPackageList.Contains($list[$i])) {
                                [void]$TargetedPackageList.Add($list[$i]);
                                $targetedcount++;
                            }
                        }
                    }
                }
                $index++;
            } while ($index -lt $count);
        } while ($targetedcount -gt 0);
    }


    # Sorts and outputs the information of all packages in the targeted list

    $TargetedPackageList.Sort();
    $TargetedPackageList `
    | ForEach-Object -Begin {
        $urlbuf = New-Object System.Text.StringBuilder 256;
        [void]$urlbuf.Append($Mirror);
    } `
    {
        $packname = $_;
        $packobj = $PackageMap.Item($packname);
        if ($packobj -ne $null) {
            if (($PackageInstalledMap -ne $null) `
                -and ($PackageInstalledMap.Contains($packname))) {
                $verobj = GetCygwinVersion $packobj.($FIELD_VERSION);
                $result = CompareCygwinVersion $verobj $PackageInstalledMap.Item($packname);
                $state = "";
                if ($result -gt 0) {
                    $state = $STATE_UPDATED;
                } elseif ($result -lt 0) {
                    $state = $STATE_OLDER;
                }
                $packobj.($FIELD_STATE) = $state;
            }
            $packobj | Add-Member NoteProperty $FIELD_NAME $packname;

            if ($Download.IsPresent) {

                # Downloads the package whose state is 'New' or 'Updated'
                # in the targeted list from the mirror site

                $urlbuf.Length = $Mirror.Length;
                $url = $urlbuf.Append($packobj.($FIELD_PATH)).ToString();
                $packobj `
                | Add-Member -PassThru NoteProperty ($FIELD_DATE) $null `
                | Add-Member NoteProperty ($FIELD_URL) $url;

                DownloadCygwinPackage $packobj $DownloadParam;
            }

            Write-Output $packobj;
        }
    }
} catch [System.Net.WebException] {
    $exception = $_.Exception;
    if ($exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
        Write-Error "Mirror '$Mirror' is not found" -Category InvalidArgument;
    } else {
        Write-Error -Exception $exception;
    }
    exit 1;
} catch [System.IO.IOException] {
    Write-Error -Exception $_.Exception;
    exit 1;
} finally {
    if ($response -ne $null) {
        $response.Close();
    }
    if ($reader -ne $null) {
        $reader.Close();
    }
    [System.IO.Directory]::SetCurrentDirectory($SystemDir);
    [Console]::CursorVisible = $ConsoleCursorVisible;
}
