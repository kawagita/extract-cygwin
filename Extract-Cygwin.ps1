# Extracts the information of packages from Cygwin setup.ini.
# Copyright(C) 2018-2025 Yoshinori Kawagita

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

.PARAMETER Depends
    Targets Cygwin packages needed by other packages, same as -Requires.

.PARAMETER Download
    Downloads Cygwin installer, setup.ini, and packages whose state are 'New'. If setup.ini is
    older than the same file on the root of x86 or x86_64 directory, those are never downloaded.

.PARAMETER Local
    Reads the version of Cygwin packages which have already been installed to the specified path
    in the local. If this parameter is not specified, the state of all packages is always 'New'.

.PARAMETER Mirror
    Sets the mirror site to the specified URL with -Download.

.PARAMETER Package
    Targets Cygwin packages of the specified name.

.PARAMETER PackageSet
    Targets Cygwin packages downloaded to the directory of the specified name under 'x86/release/'
    or 'x86_64/release/' from the root.

.PARAMETER Quiet
    Quiets for extracting Cygwin setup.ini and downloading files.

.PARAMETER Regex
    Targets Cygwin packages whose name matchs the specified regular expression.

.PARAMETER Requires
    Targets Cygwin packages needed by other packages, same as -Depends.

.PARAMETER Root
    Sets the root of x86 or x86_64 directory to the specified path.

.PARAMETER Source
    Targets Cygwin source packages of the specified name.

.PARAMETER Supplement
    Outputs the specified information of packages extracted from setup.ini.

.PARAMETER TargetLocalPackage
    Targets Cygwin packages which have already been installed to the path specified by -Local.

.PARAMETER TimeMachine
    Downloads Cygwin setup.ini and packages for Windows 2000, XP, Vista, or 7 from the Cygwin Time
    Machine mirror site (http://ctm.crouchingtigerhiddenfruitbat.org/pub/cygwin/circa/).

.LINK
    Cygwin Project:      https://cygwin.com/
    Cygwin Time Machine: http://www.crouchingtigerhiddenfruitbat.org/Cygwin/timemachine.html
#>

# Parametes of this script

param(
    [parameter(Mandatory=$true)]
    [ValidateSet('x86', 'x86_64')]
    [string]$Arch,
    [string[]]$Category=@(),
    [string]$Country="",
    [switch]$Depends,
    [switch]$Download,
    [string]$Local="",
    [string]$Mirror="",
    [string[]]$Package=@(),
    [string[]]$PackageSet=@(),
    [switch]$Quiet,
    [string[]]$Regex=@(),
    [switch]$Requires,
    [string]$Root="",
    [string[]]$Source=@(),
    [ValidateSet('Conflicts', 'Hash', 'LongDescription', 'Obsoletes', 'ReplaceVersions')]
    [string[]]$Supplement=@(),
    [switch]$TargetLocalPackage,
    [ValidateSet('2000', 'XP', 'Vista', '7')]
    [string]$TimeMachine=""
)

if ($Root -ne "") {
    New-Item $Root -ItemType Directory -Force > $null 2>&1;
    if (-not $?) {
        Write-Error "Specified root is not writable" -Category InvalidArgument;
        exit 1;
    }
}

# The path of Cygwin installed database or source packages

$CYGWIN_INSTALLED_DATABASE = 'etc/setup/installed.db';
$CYGWIN_INSTALLED_PACKAGE_SUFFIX_EXPR = '\.tar\.[a-z0-9]+$';
$CYGWIN_INSTALLED_SOURCE_PATH = 'usr/src/';
$CYGWIN_INSTALLED_SOURCE_DIRECTORY_EXPR = '^(.+)-([0-9].+)\.src$';

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

$CYGWIN_WEBSITE = 'https://cygwin.com/';

# The cygwin mirror list

$CYGWIN_MIRROR_LIST = $CYGWIN_WEBSITE + 'mirrors.lst';

# Fields of the information extracted from setup.ini

$FIELD_NAME = 'Name';
$FIELD_DESCRIPTION = 'Description';
$FIELD_LONG_DESCRIPTION = 'LongDescription';  # Specified by -Supplement
$FIELD_CATEGORY = 'Category';
$FIELD_VERSION = 'Version';
$FIELD_VERSION_LABEL = 'VersionLabel';        # Temporary field
$FIELD_REPLACE_VERSIONS = 'ReplaceVersions';  # Specified by -Supplement (Optional)
$FIELD_INSTALL = 'Install';                   # Added for the package specified by -Package
$FIELD_INSTALL_TARGETED = 'InstallTargeted';  # Temporary field
$FIELD_SOURCE = 'Source';                     # Added for the package specified by -Source
$FIELD_SOURCE_TARGETED = 'SourceTargeted';    # Temporary field
$FIELD_PATH = 'Path';                         # Added to Install and Source field
$FIELD_SIZE = 'Size';;                        # Added to Install and Source field
$FIELD_HASH = 'Hash';                         # Added to Install and Source field by -Supplement
$FIELD_DATE = 'Date';                         # Added to Install and Source field for the download
$FIELD_STATE = 'State';                       # Added to Install and Source field
$FIELD_REQUIRES = 'Requires';                 # Replaceed with Depends field
$FIELD_DEPENDS = 'Depends';                   # (Optional)
$FIELD_CONFLICTS = 'Conflicts';               # Specified by -Supplement (Optional)
$FIELD_OBSOLETES = 'Obsoletes';               # Specified by -Supplement (Optional)
$FIELD_PROVIDES = 'Provides';                 # (Optional)
$FIELD_BUILD_DEPENDS = 'BuildDepends';        # Added for the package specified by -Source
$FIELD_RELEASE = 'Release';                   # Added to the object of setup.ini
$FIELD_ARCH = 'Arch';                         # Added to the object of setup.ini
$FIELD_MINIMUM_VERSION = 'MinimumVersion';    # Added to the object of setup.ini
$FIELD_TIMESTAMP = 'Timestamp';               # Added to the object of setup.ini
$FIELD_MIRROR = 'Mirror';                     # Added to the object of setup.ini
$FIELD_URL = 'URL';                           # Added to the object of the installer

$FIELD_PATH_EXPR = '(.*/)?([-+.0-9A-Za-z_]+)$';
$FIELD_INSTALL_OR_SOURCE_EXPR = `
    '(([norarchx864_]+/)?release/(_obsolete/)?([^ /]+)(/[^ /]+)+) ([0-9]+) ([+/=0-9A-Za-z]+)$';
$DEPENDED_PACKAGE_SUFFIX_EXPR = '\((=|<=?|>=?)[0-9].*\)$';

# The state of package's file on the mirror

$STATE_PENDING = 'Pending';
$STATE_NEW = 'New';
$STATE_UNCHANGED = 'Unchanged';
$STATE_OLDER = 'Older';
$STATE_NOT_FOUND = 'Not Found';
$STATE_ERROR = 'Error';

# Returns the Cygwin mirror site selected randomly for the specified country.
#
# $Country  a country name

function GetCygwinMirror([string]$Country) {
    if ($Country -eq "") {
        $Country = ([System.Globalization.RegionInfo]::CurrentRegion).EnglishName;
    }
    if ($Country.StartsWith('Hong Kong')) {
        $Country = 'Hong Kong';
    } elseif ($Country -eq 'United Kingdom') {
        $Country = 'UK';
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

            if (($Country -eq $field[2]) -or ($Country -eq $field[3])) {
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

# The length of the hash value by which the download package is verified

$HASH_LENGTH_MD5 = 32;
$HASH_LENGTH_SHA512 = 128;

# Downloads the file for the specified object from the mirror site.
#
# $FileObject      the file object of installer, setup.ini, or a package
# $DownloadParam   the object of download parameters
# $DownloadUrl     the download URL specified directly for the installer

function DownloadCygwinFile(
    [parameter(Mandatory=$true)][Object]$FileObject,
    [parameter(Mandatory=$true)][Object]$DownloadParam, [string]$DownloadUrl="") {
    $response = $null;
    $stream = $null;
    $writer = $null;
    $url = $DownloadUrl;
    $state = $FileObject.($FIELD_STATE);
    $size = 0L;
    $date = $null;
    $filematch = $DownloadParam.FilePathRegex.Match($FileObject.($FIELD_PATH));
    $filepath = $DownloadParam.Root + $FileObject.($FIELD_PATH);
    $fileparent = $DownloadParam.Root + $filematch.Groups[1].Value;
    $dlfile = $filematch.Groups[2].Value;
    $dlpath = $DownloadParam.Temp + $dlfile;
    $setupdownloaded = $state -eq $STATE_PENDING;

    try {
        if ($url -eq "") {
            $url = $DownloadParam.UrlBuilder.Append($FileObject.($FIELD_PATH)).ToString();
        }

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

        if ($setupdownloaded -or $FileObject.($FIELD_SIZE).Equals($size)) {
            if (($state -eq $STATE_UNCHANGED) -or ($state -eq $STATE_OLDER)) {

                # Never download the package if the same has been installed to the local
                # and it's newer or unchaned, and its state has been set for the object

                return;
            }
            $FileObject.($FIELD_SIZE) = $size;

            $fileobj = Get-Item $filepath 2> $null;
            if ($fileobj -ne $null) {
                $result = $fileobj.LastWriteTime.CompareTo($date);
                if ($result -ge 0) {
                    if ($setupdownloaded) {

                        # Never download Cygwin installer or setup.ini if the same file exists on
                        # the path and it's newer or unchanged, and its state is set for the object

                        if ($result -eq 0) {
                            $state = $STATE_UNCHANGED;
                        } else {
                            $state = $STATE_OLDER;
                        }
                    }
                    return;
                }

                # Downloads the package only if the same file is older on the path
            }
            $state = $STATE_NEW;

            # Downloads and writes file data to the temporary file from http response

            if ($response -eq $null) {
                $response = GetResponse $url ([System.Net.WebRequestMethods+Ftp]::DownloadFile);
            }

            $writer = New-Object System.IO.FileStream $dlpath, `
                                                      ([System.IO.FileMode]::Create), `
                                                      ([System.IO.FileAccess]::Write);
            $stream = $response.GetResponseStream();
            $DownloadParam.Progress.Start($dlfile, $response.ContentLength, $true);

            $length = $stream.Read($DownloadParam.Buffer, 0, $DownloadParam.Buffer.Length);
            if ($length -gt 0) {
                do {
                    $DownloadParam.Progress.Increse($length);
                    $DownloadParam.Progress.Show();
                    $writer.Write($DownloadParam.Buffer, 0, $length);
                    $length = $stream.Read($DownloadParam.Buffer, 0, $DownloadParam.Buffer.Length);
                } while ($length -gt 0);
            }
            $DownloadParam.Progress.End();
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
                    $hashvalue = $FileObject.($FIELD_HASH);
                    $dlhash = "";
                    $dlcheck = $true;
                    $provider = $null;

                    if ($hashvalue.Length -eq $HASH_LENGTH_MD5) {
                        $provider = $DownloadParam.MD5CryptoServiceProvider;
                        if ($provider -eq $nul) {
                            $provider = `
                                [System.Security.Cryptography.MD5CryptoServiceProvider]::new();
                            $DownloadParam.MD5CryptoServiceProvider = $provider;
                        }
                    } elseif ($hashvalue.Length -eq $HASH_LENGTH_SHA512) {
                        $provider = $DownloadParam.SHA512CryptoServiceProvider;
                        if ($provider -eq $nul) {
                            $provider = `
                                [System.Security.Cryptography.SHA512CryptoServiceProvider]::new();
                            $DownloadParam.SHA512CryptoServiceProvider = $provider;
                        }
                    }
                    if ($provider -ne $null) {
                        $stream = $dlobj.OpenRead();
                        try {
                            $str = [System.BitConverter]::ToString($provider.ComputeHash($stream));
                            $dlhash = $str.Replace('-', "").ToLower();
                        } finally {
                            $stream.Close();
                        }
                        $dlcheck = $hashvalue.Equals($dlhash);
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

        $FileObject.($FIELD_DATE) = $date;
        $FileObject.($FIELD_STATE) = $state;
    }
}

# Returns the HTTP or FTP reqponse for the specified URL.
#
# $URL     the request URL
# $Method  the request method

function GetResponse([parameter(Mandatory=$true)][string]$URL, [string]$Method="") {
    $request = [System.Net.WebRequest]::Create($URL);
    $request.KeepAlive = $false;
    if ($url.StartsWith('ftp://')) {
        $request.Method = $Method;
    }
    return $request.GetResponse();
}


# Returns the file object of Cygwin installer, setup.ini, and packages.
#
# $FileDownloaded  true if the file is downloaded, otherwise, false
# $FilePath        the file path from the root of 'x86' or 'x86_64' directory
# $FileSize        the size of a file
# $FileHashValue   the hash value of a file
# $FileState       the state of installer, setup.ini, or a package

function CreateFileObject(
    [parameter(Mandatory=$true)][boolean]$FileDownloaded,
    [parameter(Mandatory=$true)][string]$FilePath, [long]$FileSize=0L,
    [string]$FileHashValue="", [string]$FileState=$STATE_PENDING) {
    $fileobj = New-Object PSObject -Prop @{
        $FIELD_PATH = $FilePath;
        $FIELD_SIZE = $FileSize;
        $FIELD_HASH = $FileHashValue;
        $FIELD_STATE = $FileState;
    };
    if ($FileDownloaded) {
        $fileobj | Add-Member NoteProperty ($FIELD_DATE) $null;
    }
    return $fileobj;
}

# The array of fixed fields written to the output stream for a package

$FIXED_FIELDS = @($FIELD_NAME, $FIELD_DESCRIPTION, $FIELD_CATEGORY, $FIELD_VERSION);
$FIXED_LONG_FIELDS = `
    @($FIELD_NAME, $FIELD_DESCRIPTION, $FIELD_LONG_DESCRIPTION, $FIELD_CATEGORY, $FIELD_VERSION);

$FIXED_FILE_FIELDS = @($FIELD_PATH, $FIELD_SIZE, $FIELD_STATE);
$FIXED_FILE_CHECKED_FIELDS = @($FIELD_PATH, $FIELD_SIZE, $FIELD_HASH, $FIELD_STATE);
$FIXED_DOWNLOAD_FIELDS = @($FIELD_PATH, $FIELD_SIZE, $FIELD_DATE, $FIELD_STATE);
$FIXED_DOWNLOAD_CHECKED_FIELDS = `
    @($FIELD_PATH, $FIELD_SIZE, $FIELD_HASH, $FIELD_DATE, $FIELD_STATE);

$FIXED_INSTALL_FIELDS = `
    @($FIELD_NAME, $FIELD_DESCRIPTION, $FIELD_CATEGORY, $FIELD_VERSION,
    $FIELD_INSTALL, $FIELD_DEPENDS);
$FIXED_INSTALL_LONG_FIELDS = `
    @($FIELD_NAME, $FIELD_DESCRIPTION, $FIELD_LONG_DESCRIPTION, $FIELD_CATEGORY, $FIELD_VERSION,
    $FIELD_INSTALL, $FIELD_DEPENDS);

# Returns the information selected for the specified file object of a package.
#
# $FileObject       the file object of installer, setup.ini, or a package
# $HashValueOutput  true if the hash value is output, otherwise, false

function SelectFileInformation(
    [parameter(Mandatory=$true)][Object]$FileObject, [boolean]$HashValueOutput=$false) {
    $filefields = $FIXED_FILE_FIELDS;
    if ($HashValueOutput) {
        if ($FileObject.($FIELD_DATE) -ne $null) {
            $filefields = $FIXED_DOWNLOAD_CHECKED_FIELDS;
        } else {
            $filefields = $FIXED_FILE_CHECKED_FIELDS;
        }
    } elseif ($FileObject.($FIELD_DATE) -ne $null) {
        $filefields = $FIXED_DOWNLOAD_FIELDS;
    }
    return $FileObject | Select-Object $filefields;
}

# The label for the version of Cygwin packages

$VERSION_LABEL_CURRENT = 'curr'
$VERSION_LABEL_PREVIOUS = 'prev'
$VERSION_LABEL_TEST = 'test'

# Returns the information selected for the specified object of a package.
#
# $PackageObject  the object of installer, setup.ini, or a package
# $SelectParam    the object of selection parameters

function SelectPackageInformation(
    [parameter(Mandatory=$true)][Object]$PackageObject, [parameter(Mandatory=$true)]$SelectParam) {
    $instobj = $PackageObject.($FIELD_INSTALL);
    $srcobj = $PackageObject.($FIELD_SOURCE);
    $fieldlist = $SelectParam.FieldList;
    $fieldcount = $fieldlist.Count;
    $fieldfixed = $true;

    # Removes optional and/or supplemetal fields appended previously from the field list.

    while ($fieldcount -gt $SelectParam.FixedFieldCount) {
        $fieldcount--;
        $fieldlist.RemoveAt($fieldcount);
    }

    $PackageObject.($FIELD_CATEGORY) = $PackageObject.($FIELD_CATEGORY).Split(' ');

    if ($PackageObject.($FIELD_VERSION_LABEL) -eq $VERSION_LABEL_TEST) {

        # Appends '(Test)' to the version if the version description is test

        $PackageObject.($FIELD_VERSION) += ' (Test)';
    }

    if ($SelectParam.ReplaceVersionsOutput `
        -and ($PackageObject.($FIELD_REPLACE_VERSIONS) -ne $null)) {
        [void]$fieldlist.Add($FIELD_REPLACE_VERSIONS);
        $fieldfixed = $false;
    }
    if ($instobj -ne $null) {
        $PackageObject.($FIELD_INSTALL) = SelectFileInformation $instobj $SelectParam.HashOutput;
        [void]$fieldlist.Add($FIELD_INSTALL);
    }
    if ($srcobj -ne $null) {
        $PackageObject.($FIELD_SOURCE) = SelectFileInformation $srcobj $SelectParam.HashOutput;
        [void]$fieldlist.Add($FIELD_SOURCE);
        $fieldfixed = $false;
    }

    # Replaces the string with the array of values in the field added to the object

    if ($PackageObject.($FIELD_DEPENDS) -ne $null) {
        $PackageObject.($FIELD_DEPENDS) = `
            $PackageObject.($FIELD_DEPENDS).Replace(' ', "").Split(',');
        [void]$fieldlist.Add($FIELD_DEPENDS);
        $fieldfixed = $false;
    } elseif ($PackageObject.($FIELD_REQUIRES) -ne $null) {
        $PackageObject.($FIELD_DEPENDS) = $PackageObject.($FIELD_REQUIRES).Split(' ');
        [void]$fieldlist.Add($FIELD_DEPENDS);
        $fieldfixed = $false;
    }
    if ($SelectParam.ObsoletesOutput -and ($PackageObject.($FIELD_OBSOLETES) -ne $null)) {
        $PackageObject.($FIELD_OBSOLETES) = `
            $PackageObject.($FIELD_OBSOLETES).Replace(' ', "").Split(',');
        [void]$fieldlist.Add($FIELD_OBSOLETES);
        $fieldfixed = $false;
    }
    if ($SelectParam.ConflictsOutput -and ($PackageObject.($FIELD_CONFLICTS) -ne $null)) {
        $PackageObject.($FIELD_CONFLICTS) = `
            $PackageObject.($FIELD_CONFLICTS).Replace(' ', "").Split(',');
        [void]$fieldlist.Add($FIELD_CONFLICTS);
        $fieldfixed = $false;
    }
    if ($PackageObject.($FIELD_PROVIDES) -ne $null) {
        $PackageObject.($FIELD_PROVIDES) = `
            $PackageObject.($FIELD_PROVIDES).Replace(' ', "").Split(',');
        [void]$fieldlist.Add($FIELD_PROVIDES);
        $fieldfixed = $false;
    }
    if ($PackageObject.($FIELD_BUILD_DEPENDS) -ne $null) {
        $PackageObject.($FIELD_BUILD_DEPENDS) = `
            $PackageObject.($FIELD_BUILD_DEPENDS).Replace(' ', "").Split(',');
        [void]$fieldlist.Add($FIELD_BUILD_DEPENDS);
        $fieldfixed = $false;
    }

    if ($fieldfixed) {
        if ($fieldlist.Contains($FIELD_LONG_DESCRIPTION)) {
            $fieldlist = $FIXED_INSTALL_LONG_FIELDS;
        } else {
            $fieldlist = $FIXED_INSTALL_FIELDS;
        }
    }

    return $PackageObject | Select-Object $fieldlist;
}

# The architecture to install the Cygwin

$ARCH_X86 = 'x86';
$ARCH_X64 = 'x86_64';

# The Cygwin Time Machine mirror site and its URL

$TIME_MACHINE_MIRROR = 'http://ctm.crouchingtigerhiddenfruitbat.org/pub/cygwin/circa/';
$TIME_MACHINE_X64_MIRROR = 'http://ctm.crouchingtigerhiddenfruitbat.org/pub/cygwin/circa/64bit/';
$TIME_MACHINE_LAST_MIRRORS = @{
    '2000' = @{ $ARCH_X86 = $TIME_MACHINE_MIRROR + '2013/06/04/121035/' }
    'XP' = @{
        $ARCH_X86 = $TIME_MACHINE_MIRROR + '2016/08/30/104223/'
        $ARCH_X64 = $TIME_MACHINE_X64_MIRROR + '2016/08/30/104235/'
    }
    'Vista' = @{
        $ARCH_X86 = $TIME_MACHINE_MIRROR + '2021/10/28/175116'
        $ARCH_X64 = $TIME_MACHINE_X64_MIRROR + '2021/10/28/174906/'
    }
    '7' = @{
        $ARCH_X86 = $TIME_MACHINE_MIRROR + '2022/11/23/063457/'
        $ARCH_X64 = $TIME_MACHINE_X64_MIRROR + '2024/01/30/231215/'
    }
};

# The timestamp written to the header of setup.ini for the version of setup.exe

$TIME_MACHINE_SETUP_LEGACY_VERSION = [float]2.674;
$TIME_MACHINE_SETUP_LAST = [float]2.774;
$TIME_MACHINE_SETUP_VERSIONS = @(
    [float]2.679, [float]2.685, [float]2.738, [float]2.740, [float]2.741, [float]2.745,
    [float]2.747, [float]2.749, [float]2.752, [float]2.754, [float]2.755, [float]2.756,
    [float]2.762, [float]2.766, [float]2.767, [float]2.773, $TIME_MACHINE_SETUP_LAST
);
$TIME_MACHINE_SETUP_X86_X64_LAST = [float]2.926;
$TIME_MACHINE_SETUP_X86_X64_VERSIONS = @(
    [float]2.844, [float]2.850, [float]2.852, [float]2.859, [float]2.864, [float]2.867,
    [float]2.870, [float]2.871, [float]2.872, [float]2.873, [float]2.874, [float]2.876,
    [float]2.879, [float]2.880, [float]2.881, [float]2.882, [float]2.883, [float]2.884,
    [float]2.888, [float]2.889, [float]2.877, [float]2.878, [float]2.891, [float]2.893,
    [float]2.895, [float]2.897, [float]2.898, [float]2.900, [float]2.901, [float]2.903,
    [float]2.904, [float]2.905, [float]2.908, [float]2.909, [float]2.911, [float]2.912,
    [float]2.915, [float]2.917, [float]2.918, [float]2.919, [float]2.923, [float]2.924,
    [float]2.925, $TIME_MACHINE_SETUP_X86_X64_LAST
);

$TIME_MACHINE_SETUP_TIMESTAMP_LEGACY = 1259724034L;
$TIME_MACHINE_SETUP_TIMESTAMP_2774 = 1372443636L;
$TIME_MACHINE_SETUP_TIMESTAMP_2774_VERSION = [float]2.774;
$TIME_MACHINE_SETUP_TIMESTAMP_2874 = 1473388972L;
$TIME_MACHINE_SETUP_TIMESTAMP_2874_VERSION = [float]2.874;
$TIME_MACHINE_SETUP_TIMESTAMP_2909 = 1640710562L;
$TIME_MACHINE_SETUP_TIMESTAMP_2909_VERSION = [float]2.909;
$TIME_MACHINE_SETUP_TIMESTAMP_2924 = 1677964491L;
$TIME_MACHINE_SETUP_TIMESTAMP_2924_VERSION = [float]2.924;
$TIME_MACHINE_SETUP_TIMESTAMP_2926 = 1706773736L;

# Returns the available version of Cygwin installer.
#
# $SetupTimestamp  the timestamp of setup.ini
# $SetupVersion    the version of setup.ini

function GetCygwinInstallerVersion(
    [parameter(Mandatory=$true)][float]$SetupTimestamp,
    [parameter(Mandatory=$true)][string]$SetupVersion) {
    if ($SetupVersion -ne "") {
        $match = ([Regex]('^[2-9].[0-9][0-9][0-9]')).Match($SetupVersion);
        if ($match.Success) {
            $setupver = [float]::Parse($match.Groups[0].Value);
            if ($setupver -gt $TIME_MACHINE_SETUP_X86_X64_LAST) {
                return $setupver;
            } elseif ($setupver -le $TIME_MACHINE_SETUP_LEGACY_VERSION) {
                return $TIME_MACHINE_SETUP_LEGACY_VERSION;
            }
            $setupvers = $TIME_MACHINE_SETUP_X86_X64_VERSIONS;
            if ($setupver -le $TIME_MACHINE_SETUP_LAST) {
                $setupvers = $TIME_MACHINE_SETUP_VERSIONS;
            }
            for ($i = $setupvers.Count - 2; $i -ge 0; $i--) {
                if ($setupver -gt $setupvers[$i]) {
                    return $setupvers[$i + 1];
                }
            }
            return $setupvers[0];
        }
    }

    # Decides the version from the timestamp if not read from setup.ini

    if ($setuptimestamp -gt $TIME_MACHINE_SETUP_TIMESTAMP_2924) {
        return $TIME_MACHINE_SETUP_TIMESTAMP_2926_VERSION;
    } elseif ($setuptimestamp -gt $TIME_MACHINE_SETUP_TIMESTAMP_2909) {
        return $TIME_MACHINE_SETUP_TIMESTAMP_2924_VERSION;
    } elseif ($setuptimestamp -gt $TIME_MACHINE_SETUP_TIMESTAMP_2874) {
        return $TIME_MACHINE_SETUP_TIMESTAMP_2909_VERSION;
    } elseif ($setuptimestamp -gt $TIME_MACHINE_SETUP_TIMESTAMP_2774) {
        return $TIME_MACHINE_SETUP_TIMESTAMP_2874_VERSION;
    } elseif ($setuptimestamp -gt $TIME_MACHINE_SETUP_TIMESTAMP_LEGACY) {
        return $TIME_MACHINE_SETUP_TIMESTAMP_2774_VERSION;
    }
    return $TIME_MACHINE_SETUP_LEGACY_VERSION;
}

# The file or directory names of setup.exe and setup.ini

$SETUP_PREFIX = 'setup-';
$SETUP_X86_PREFIX = $SETUP_PREFIX + $ARCH_X86;
$SETUP_X64_PREFIX = $SETUP_PREFIX + $ARCH_X64;

$SETUP_X86_EXE = $SETUP_X86_PREFIX + '.exe';
$SETUP_X64_EXE = $SETUP_X64_PREFIX + '.exe';
$SETUP_LEGACY_EXE = $SETUP_PREFIX + 'legacy.exe';
$SETUP_INI = 'setup.ini';

$SETUP_DIRECTORY = 'setup/';
$SETUP_LEGACY_DIRECTORY = 'legacy/';
$SETUP_SNAPSHOTS_DIRECTORY = 'snapshots/';

$SETUP_INSTALLER_NAME = 'Cygwin Installer';
$SETUP_LEGACY_INSTALLER_NAME = 'Cygwin Legacy Installer';

$SETUP_INI_FIXED_FIELDS = @(
    $FIELD_NAME, $FIELD_RELEASE, $FIELD_ARCH, $FIELD_TIMESTAMP, $FIELD_MINIMUM_VERSION,
    $FIELD_VERSION, $FIELD_INSTALL, $FIELD_MIRROR);
$SETUP_EXE_FIXED_FIELDS = @($FIELD_NAME, $FIELD_VERSION, $FIELD_INSTALL, $FIELD_URL);

# Returns the object to set the information of Cygwin installer.
#
# $SetupObject  the object of setup.ini

function CreateCygwinInstallerObject([parameter(Mandatory=$true)][Object]$SetupObject) {
    $setuparch = $SetupObject.($FIELD_ARCH);
    $setupversion = `
        GetCygwinInstallerVersion $SetupObject.($FIELD_TIMESTAMP) $SetupObject.($FIELD_VERSION);
    $setupobj = New-Object PSObject -Prop @{
        $FIELD_NAME = $SETUP_INSTALLER_NAME;
        $FIELD_VERSION = $setupversion;
        $FIELD_INSTALL = $null;
        $FIELD_URL = $null;
    };
    $dlfileprefix = $SETUP_X86_PREFIX + '-';
    $dlmirror = $TIME_MACHINE_MIRROR -replace '[a-z]+/$', $SETUP_DIRECTORY;
    switch ($setuparch) {
        $ARCH_X64 {
            $setupobj.($FIELD_INSTALL) = CreateFileObject $true $SETUP_X64_EXE;
            if ($setupversion -gt $TIME_MACHINE_SETUP_X86_X64_LAST) {

                # Uses the Cygwin installer downloaded from cygwin.com if greater than 2.926

                $verstr = [String]::Format('{0:f3}', $setupversion);
                $dlfile = $SETUP_PREFIX + $verstr + "." + $setuparch + '.exe';
                $setupobj.($FIELD_URL) = $CYGWIN_WEBSITE + $SETUP_DIRECTORY + $dlfile;
                return $setupobj;
            }
            $dlfileprefix = $SETUP_X64_PREFIX + '-';
            break;
        }
        $ARCH_X86 {
            $setupobj.($FIELD_INSTALL) = CreateFileObject $true $SETUP_X86_EXE;
            if ($setupversion -le $TIME_MACHINE_SETUP_LEGACY_VERSION) {

                # Uses the legacy installer downloaded from Cygwin Time Machine if less than 2.674

                $setupobj.($FIELD_NAME) = $SETUP_LEGACY_INSTALLER_NAME;
                $setupobj.($FIELD_URL) = $dlmirror + $SETUP_LEGACY_DIRECTORY + $SETUP_LEGACY_EXE;
                return $setupobj;
            } elseif ($setupversion -le $TIME_MACHINE_SETUP_LAST) {
                $dlfileprefix = $SETUP_PREFIX;
            }
            break;
        }
    }

    # Uses the Cygwin installer of snapshots downloaded from Cygwin Time Machine

    $dlfile = $dlfileprefix + [String]::Format('{0:f3}', $setupversion) + '.exe';
    $setupobj.($FIELD_URL) = $dlmirror + $SETUP_SNAPSHOTS_DIRECTORY + $dlfile;
    return $setupobj;
}

if ($TimeMachine -ne "") {
    $Mirror = $TIME_MACHINE_LAST_MIRRORS[$TimeMachine].Item($Arch);
    if ([String]::IsNullOrEmpty($Mirror)) {
        Write-Error "x86 must be specified for Windows 2000" -Category InvalidArgument;
        exit 1;
    }
    $Download = [switch]$true;
} elseif ($Mirror.StartsWith($TIME_MACHINE_MIRROR)) {
    if ($Mirror.StartsWith($TIME_MACHINE_X64_MIRROR)) {
        if ($Arch -eq $ARCH_X86) {
            Write-Error "x86_64 must be specified for this mirror site" -Category InvalidArgument;
            exit 1;
        }
    } elseif ($Arch -eq $ARCH_X64) {
        Write-Error "x86 must be specified for this mirror site" -Category InvalidArgument;
        exit 1;
    }
}

# Sets the object of setup.ini on 'x86' or 'x86_64' directory

$SetupIni = New-Object PSObject -Prop @{
    $FIELD_NAME = 'setup.ini';
    $FIELD_RELEASE = "";
    $FIELD_ARCH = $Arch;
    $FIELD_TIMESTAMP = 0L;
    $FIELD_MINIMUM_VERSION = "";
    $FIELD_VERSION = "";
};
$SetupIniPath = $null;
if ($Arch -eq $ARCH_X86) {
    $SetupIniPath = $ARCH_X86 + '/' + $SETUP_INI;
} else {
    $SetupIniPath = $ARCH_X64 + '/' + $SETUP_INI;
}
$SetupIniState = $STATE_PENDING;

# The progress of extracting or downloading package

$Progress = $null;

if ($Quiet.IsPresent) {
    $Progress = New-Object PSObject `
    | Add-Member -PassThru ScriptMethod 'Start' { } `
    | Add-Member -PassThru ScriptMethod 'Increse' { } `
    | Add-Member -PassThru ScriptMethod 'Show' { } `
    | Add-Member -PassThru ScriptMethod 'End' { };
} else {
    $ProgressLimit = 50;
    if ([Console]::BufferWidth -le 60) {
        $ProgressLimit = [Console]::BufferWidth - 10;
    };
    $Progress = New-Object PSObject -Prop @{
        'FileName' = "";
        'FileSize' = 0;
        'ByteLength' = 0;
        'Percent' = 0;
        'Limit' = $ProgressLimit;
        'Count' = 0;
        'CountRate' = 0.0;
        'CountBuffer' = [System.Text.StringBuilder]::new($ProgressLimit + 8);
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
                [void]$this.CountBuffer.Append(
                    '=>').Append(' ', $this.Limit - $count - 1).Append('] ');
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
}

# The object of download parameters

$DownloadParam = $null;
$DownloadRoot = $Root -replace '\\', '/' -replace '[^/]$', '$&/';

if ($Download.IsPresent) {
    $DownloadParam = New-Object PSObject -Prop @{
        'Root' = $DownloadRoot;
        'Temp' = $env:TEMP -replace '\\', '/' -replace '[^/]$', '$&/';
        'FilePathRegex' = [Regex]($FIELD_PATH_EXPR);
        'Buffer' = $null;
        'UrlBuilder' = [System.Text.StringBuilder]::new(256);
        'MD5CryptoServiceProvider' = $null;
        'SHA512CryptoServiceProvider' = $null;
        'Progress' = $Progress;
    };
}

# The object of selection parameters

$SelectParam = New-Object PSObject -Prop @{
    'FieldList' = $null;
    'FixedFieldCount' = 0;
    'ReplaceVersionsOutput' = $Supplement.Contains($FIELD_REPLACE_VERSIONS);
    'HashOutput' = $Supplement.Contains($FIELD_HASH);
    'ObsoletesOutput' = $Supplement.Contains($FIELD_OBSOLETES);
    'ConflictsOutput' = $Supplement.Contains($FIELD_CONFLICTS);
};
if ($Supplement.Contains($FIELD_LONG_DESCRIPTION)) {
    $SelectParam.FieldList = [System.Collections.ArrayList]::new($FIXED_LONG_FIELDS);
    $SelectParam.FixedFieldCount = $FIXED_LONG_FIELDS.Count;
} else {
    $SelectParam.FieldList = [System.Collections.ArrayList]::new($FIXED_FIELDS);
    $SelectParam.FixedFieldCount = $FIXED_FIELDS.Count;
}

# The list of target packages extracted from setup.ini

$TargetedPackageList = [System.Collections.ArrayList]::new(256);
$TargetedLocalPackageList = @();
$TargetRegexList = @();
$TargetSpecified = $false;

if (($Category.Count + $PackageSet.Count + $Package.Count + $Source.Count) -gt 0) {
    $TargetSpecified = $true;
}
if ($Regex.Count -gt 0) {
    $TargetRegexList = [System.Collections.ArrayList]::new($Regex.Count);
    $Regex | `
    ForEach-Object {
        [void]$TargetRegexList.Add([Regex]($_));
        if (-not $?) {
            exit 1;
        }
    }
    $TargetSpecified = $true;
}

# The map of all packages read from setup.ini

$PackageMap = [Hashtable]::new(12800);
$PackageProvidedSetMap = $null;
if ($Provides.IsPresent) {
    $PackageProvidedSetMap = @{};
}

$ConsoleCursorVisible = [Console]::CursorVisible;
$SystemDir = [System.IO.Directory]::GetCurrentDirectory();
[System.IO.Directory]::SetCurrentDirectory((Get-Location).Path);
[Console]::CursorVisible = $true;

$reader = $null;
try {

    # Reads the information of packages which has already been installed in the local

    $localroot = $Local -replace '\\', '/' -replace '[^/]$', '$&/';
    $localinstmap = $null;
    $localsrcmap = $null;

    if ($localroot -ne "") {
        $packinstdb = Get-Item ($localroot + $CYGWIN_INSTALLED_DATABASE) 2> $null;
        if ($?) {
            if ($TargetLocalPackage.IsPresent) {
                $TargetedLocalPackageList = [System.Collections.ArrayList]::new(256);
            }
            $localinstmap = [Hashtable]::new(256);
            $reader = $null;
            try {

                # Reads the package's name and version from Cygwin installed.db

                $reader = $packinstdb.OpenText();
                [void]$reader.ReadLine();  # Ignores "INSTALLED.DB x"

                if ($reader.Peek() -ge 0) {
                    do {
                        $field = $reader.ReadLine().Split(' ');
                        $packname = $field[0];
                        $verstr = $field[1].Substring($packname.Length + 1) `
                                   -replace $CYGWIN_INSTALLED_PACKAGE_SUFFIX_EXPR, "";

                        if ($TargetLocalPackage.IsPresent) {
                            [void]$TargetedLocalPackageList.Add($packname);
                            $TargetSpecified = $true;
                        }
                        $localinstmap.Add($packname, (GetCygwinVersion $verstr));
                    } while ($reader.Peek() -ge 0);
                }
            } finally {
                if ($reader -ne $null) {
                    $reader.Close();
                }
            }
        }

        # Gets the version of source packages from the directory name under '/usr/src'

        $srcdirs = Get-ChildItem -Directory ($localroot + $CYGWIN_INSTALLED_SOURCE_PATH) 2> $null;
        if ($srcdirs -ne $null) {
            $localsrcmap = [Hashtable]::new(64);
            $srcdirregex = [Regex]($CYGWIN_INSTALLED_SOURCE_DIRECTORY_EXPR);
            $srcdirs | ForEach-Object {
                $match = $srcdirregex.Match($_);
                if ($match.Success) {
                    $packname = $match.Groups[1].Value;
                    $verstr = $match.Groups[2].Value;
                    $localsrcmap.Add($packname, (GetCygwinVersion $verstr));
                }
            }
        }
    }

    if ($DownloadParam -ne $null) {
        if ($Mirror -eq "") {

            # Sets the mirror site for the specified country or current region

            $Mirror = GetCygwinMirror $Country;
            if ($Mirror -eq $null) {
                Write-Error "Mirror must be specified" -Category SyntaxError;
                exit 1;
            }
        } else {
            $Mirror = $Mirror -replace '\\', '/' -replace '[^/]$', '$&/';
        }

        # Downloads setup.ini from the mirror site if the same file don't exits
        # or it's older than the downloaded file

        $instobj = CreateFileObject $true $SetupIniPath;
        $DownloadParam.Buffer = [byte[]]::new(10240);
        [void]$DownloadParam.UrlBuilder.Append($Mirror);

        DownloadCygwinFile $instobj $DownloadParam;

        $SetupIni `
        | Add-Member -PassThru NoteProperty ($FIELD_INSTALL) (SelectFileInformation $instobj) `
        | Add-Member NoteProperty ($FIELD_MIRROR) $Mirror;
        $SetupIniState = $instobj.($FIELD_STATE);

        if (($SetupIniState -eq $STATE_ERROR) -or ($SetupIniState -eq $STATE_NOT_FOUND)) {
            Write-Output $SetupIni;
            exit 0;
        }
    } elseif (-not $TargetSpecified) {
        exit 0;
    }

    # Opens setup.ini and firstly reads the setup information from the header

    $SetupIniPath = $DownloadRoot + $SetupIniPath;
    $fileobj = Get-Item $SetupIniPath 2> $null;
    if (-not $?) {
        Write-Error "Setup.ini don't exist" -Category InvalidArgument;
        exit 1;
    }

    $text = "";
    $reader = $fileobj.OpenText();
    $Progress.Start($SetupIniPath, $fileobj.Length, $false);

    while ($reader.Peek() -ge 0) {
        $text = $reader.ReadLine();
        if (-not $text.StartsWith('#')) {  # Ignores the header
            if ($text.StartsWith('@ ')) {  # Exits this loop if the first package is appeared
                break;
            }

            $index = $text.IndexOf(':');
            if ($index -gt 0) {
                $name = $text.Substring(0, $index);
                $value = $text.Substring($index + 1).Trim();

                switch ($name) {
                    'release' {  # release: cygwin
                        $SetupIni.($FIELD_RELEASE) = $value;
                        break;
                    }
                    'arch' {  # arch: x86(_64)?
                        if (($value -ne "") -and ($value -ne $SetupIni.($FIELD_ARCH))) {
                            Write-Error "Setup.ini differs from -Arch" -Category InvalidArgument;
                            exit 1;
                        }
                        break;
                    }
                    'setup-timestamp' {  # setup-timestamp: 9999999999
                        $SetupIni.($FIELD_TIMESTAMP) = [long]::Parse($value);
                        break;
                    }
                    'setup-minimum-version' {  # setup-minimum-version: 2.xxx
                        $SetupIni.($FIELD_MINIMUM_VERSION) = $value;
                        break;
                    }
                    'setup-version' {  # setup-version: 2.xxx
                        $SetupIni.($FIELD_VERSION) = $value;
                        break;
                    }
                }
            }
            $text = "";
        }
    }

    # Reads the information of all packages from setup.ini and create the object
    # of it whose name is appended to the targeted list if specified by options

    if ($TargetSpecified -and ($SetupIniState -ne $STATE_OLDER)) {
        $packinstregex = [Regex]($FIELD_INSTALL_OR_SOURCE_EXPR);
        $packname = "";
        $packobj = $null;
        $longdesc = $null;
        $textquoted = $false;
        $textignored = $false;

        do {
            $text = $text.Trim();

            if ($textquoted) {
                $textquoted = -not $text.EndsWith('"');

                if ($longdesc -ne $null) {

                    # Ends the description started from the previous line with the double quote

                    $longdesc += "`n" + ($text -replace '"$', "");
                    if (-not $textquoted) {  # ...xxx xxxxx."
                        $packobj | Add-Member NoteProperty ($FIELD_LONG_DESCRIPTION) $longdesc;
                        $longdesc = $null;
                    }
                }
            } elseif ($text.StartsWith('@ ')) {  # @ xxx
                $Progress.Show();

                $packname = $text.Substring(2).Trim();
                $packobj = New-Object PSObject -Prop @{
                    $FIELD_NAME = $packname;
                    $FIELD_DESCRIPTION = "";
                    $FIELD_CATEGORY = "";
                    $FIELD_VERSION = "";
                    $FIELD_INSTALL = $null;
                    $FIELD_INSTALL_TARGETED = $Package.Contains($packname) `
                        -or $TargetedLocalPackageList.Contains($packname);
                    $FIELD_SOURCE_TARGETED = $Source.Contains($packname);
                    $FIELD_REQUIRES = $null;
                    $FIELD_DEPENDS = $null;
                };
                $longdesc = $null;
                $textignored = $false;

                # Appends the object of all packages read from setup.ini

                $PackageMap.Add($packname, $packobj);

                if ($packobj.($FIELD_INSTALL_TARGETED) `
                    -or $packobj.($FIELD_SOURCE_TARGETED)) {  # Specified by -Package or -Source
                    [void]$TargetedPackageList.Add($packname);
                } else {
                    for ($i = 0; $i -lt $TargetRegexList.Count; $i++) {
                        if ($TargetRegexList.Item($i).IsMatch($packname)) {  # Specified by -Regex
                            $packobj.($FIELD_INSTALL_TARGETED) = $true;
                            [void]$TargetedPackageList.Add($packname);
                            break;
                        }
                    }
                }
            } elseif ($text.StartsWith('[') -and $text.EndsWith(']')) {  # Version description

                # Ignores other versions described after the current which is labeled or not

                $text = $text.Trim('[]');
                if ($packobj.($FIELD_INSTALL) -ne $null) {
                    if ($packobj.($FIELD_VERSION_LABEL) -eq $null) { # After the current version
                        $textignored = $true;
                    } else {  # The version description which follows the previous or test
                        if (($PackageProvidedSetMap -ne $null) `
                            -and ($packobj.($FIELD_PROVIDES) -ne $null)) {

                            # Removes the name from the set of packages which have the same value
                            # in provides field for the previous description

                            $packobj.($FIELD_PROVIDES).Replace(' ', "").Split(',') `
                            | ForEach-Object {
                                $provname = $_ -replace $DEPENDED_PACKAGE_SUFFIX_EXPR, "";
                                $provset = $PackageProvidedSetMap.Item($provname);
                                if ($provset.Contains($provname)) {
                                    $provset.remove($provname);
                                }
                            }
                        }

                        # Creates the object for the next version description and replaces
                        # the previous with it in the package map

                        $nextobj = New-Object PSObject -Prop @{
                            $FIELD_NAME = $packname;
                            $FIELD_DESCRIPTION = $packobj.($FIELD_DESCRIPTION);
                            $FIELD_CATEGORY = $packobj.($FIELD_CATEGORY);
                            $FIELD_VERSION = "";
                            $FIELD_INSTALL = $null;
                            $FIELD_INSTALL_TARGETED = $packobj.($FIELD_INSTALL_TARGETED);
                            $FIELD_SOURCE_TARGETED = $packobj.($FIELD_SOURCE_TARGETED);
                            $FIELD_REQUIRES = $null;
                            $FIELD_DEPENDS = $null;
                        };
                        $packobj = $nextobj;

                        if ($text -ne $VERSION_LABEL_CURRENT) {  # "[prev]" or "[test]"
                            $packobj | Add-Member NoteProperty ($FIELD_VERSION_LABEL) $text;
                        }
                        $PackageMap[$packname] = $packobj;
                    }
                } elseif ($text -ne $VERSION_LABEL_CURRENT) {  # "[prev]" or "[test]"
                    $packobj | Add-Member NoteProperty ($FIELD_VERSION_LABEL) $text;
                }
            } elseif (-not $textignored) {

                # Reads the package information name and value separated by a colon

                $index = $text.IndexOf(':');
                if ($index -ge 0) {
                    $name = $text.Substring(0, $index);
                    $value = $text.Substring($index + 1).Trim();

                    switch ($name) {
                        'sdesc' {  # sdesc: "Xxxxx xxx"
                            $packobj.($FIELD_DESCRIPTION) = $value.Trim('"');
                            break;
                        }
                        'ldesc' {  # ldesc: "Xxxxx xxx...
                            if ($Supplement.Contains($FIELD_LONG_DESCRIPTION)) {
                                $longdesc = $value.Trim('"');
                            }
                            $textquoted = -not $value.EndsWith('"');
                            if (-not $textquoted) {  # ...xxx xxxxx."
                                $packobj `
                                | Add-Member NoteProperty ($FIELD_LONG_DESCRIPTION) $longdesc;
                                $longdesc = $null;
                            }
                            break;
                        }
                        'category' {  # category: xxx yyy zzz
                            if ((-not $packobj.($FIELD_INSTALL_TARGETED)) `
                                -and (-not $packobj.($FIELD_SOURCE_TARGETED))) {
                                $categories = $value.Split(' ');
                                for ($i = 0; $i -lt $categories.Count; $i++) {
                                    if ($Category.Contains($categories[$i])) {
                                        $packobj.($FIELD_INSTALL_TARGETED) = $true;
                                        [void]$TargetedPackageList.Add($packname);
                                        break;
                                    }
                                }
                            }
                            $packobj.($FIELD_CATEGORY) = $value;
                            break;
                        }
                        'requires' {  # requires: xxx yyy zzz
                            $packobj.($FIELD_REQUIRES) = $value;
                            break;
                        }
                        'replace-versions' {  # replace-versions: xxx yyy zzz
                            if ($Supplement.Contains($FIELD_REPLACE_VERSIONS)) {
                                $packobj | Add-Member NoteProperty ($FIELD_REPLACE_VERSIONS) $value;
                            }
                            break;
                        }
                        'version' {  # version: xxx
                            $packobj.($FIELD_VERSION) = $value;
                            break;
                        }
                        'install' {
                            # install: ((x86)?/release/(_obsolete/)?(xxx)(/yyy)+) (999) (fa5b...)
                            if (-not $packobj.($FIELD_INSTALL_TARGETED)) {
                                $match = $packinstregex.Match($value);
                                if ($match.Success `
                                    -and $PackageSet.Contains($match.Groups[4].Value)) {
                                    $packobj.($FIELD_INSTALL_TARGETED) = $true;
                                    [void]$TargetedPackageList.Add($packname);
                                }
                            }
                            $packobj.($FIELD_INSTALL) = $value;
                            break;
                        }
                        'source' {
                            # source: ((x86)?/release/()?(xxx)(/yyy)+) (999) (fa5b...)
                            if ($packobj.($FIELD_SOURCE_TARGETED)) {
                                $packobj | Add-Member NoteProperty ($FIELD_SOURCE) $value;
                            }
                            break;
                        }
                        'message' {  # message: "Xxxxx xxx...
                            $textquoted = -not $value.EndsWith('"');
                        }
                        'depends' {  # depends: xxx ( >= 9.99), yyy, zzz
                            $packobj.($FIELD_DEPENDS) = $value;
                            break;
                        }
                        'depends2' {  # depends2: xxx ( >= 9.99), yyy, zzz
                            $packobj.($FIELD_DEPENDS) = $value;
                            break;
                        }
                        'obsoletes' {  # obsoletes: xxx ( >= 9.99), yyy, zzz
                            if ($Supplement.Contains($FIELD_OBSOLETES)) {
                                $packobj | Add-Member NoteProperty ($FIELD_OBSOLETES) $value;
                            }
                            break;
                        }
                        'conflicts' {  # conflicts: xxx ( >= 9.99), yyy, zzz
                            if ($Supplement.Contains($FIELD_CONFLICTS)) {
                                $packobj | Add-Member NoteProperty ($FIELD_CONFLICTS) $value;
                            }
                            break;
                        }
                        'provides' {  # provides: xxx, yyy, zzz
                            if ($PackageProvidedSetMap -ne $null) {
                                $value.Replace(' ', "").Split(',') | ForEach-Object {

                                    # Creates the set of packages which have the same value in
                                    # provides field, and adds it to the map

                                    $provname = $_ -replace $DEPENDED_PACKAGE_SUFFIX_EXPR, "";
                                    $provset = $PackageProvidedSetMap.Item($provname);
                                    if ($provset -eq $null) {
                                        $provset = [System.Collections.ArrayList]::new(16);
                                        $PackageProvidedSetMap.Add($provname, $provset);
                                    } elseif ($provset.Contains($provname)) {
                                        break;
                                    }
                                    [void]$provset.Add($provname);
                                }
                            }
                            $packobj | Add-Member NoteProperty ($FIELD_PROVIDES) $value;
                            break;
                        }
                        'build-depends' {  # build-depends: xxx ( >= 9.99), yyy, zzz
                            if ($packobj.($FIELD_SOURCE_TARGETED)) {
                                $packobj | Add-Member NoteProperty ($FIELD_BUILD_DEPENDS) $value;
                            }
                            break;
                        }
                    }
                }
            }
            $Progress.Increse($text.Length + 1);

            if ($reader.Peek() -lt 0) {
                break;
            }
            $text = $reader.ReadLine();
        } while ($true);
    }

    $Progress.End();
    $reader.Close();
    $reader = $null;

    # Downloads the installer after setup informations are set for the object of setup.ini

    if ($DownloadParam -ne $null) {
        if ($SetupIniState -eq $STATE_OLDER) {

            # Never download files from the mirror site if old setup.ini exists

            Write-Output $SetupIni | Select-Object $SETUP_INI_FIXED_FIELDS;
            exit 0;
        }
        $SetupExe = CreateCygwinInstallerObject $SetupIni;
        $instobj = $SetupExe.($FIELD_INSTALL);

        DownloadCygwinFile $instobj $DownloadParam $SetupExe.($FIELD_URL);

        $SetupExe.($FIELD_INSTALL) = SelectFileInformation $instobj;
        Write-Output $SetupExe | Select-Object $SETUP_EXE_FIXED_FIELDS;
        Write-Output $SetupIni | Select-Object $SETUP_INI_FIXED_FIELDS;

        if ($TargetedPackageList.Count -le 0) {
            exit 0;
        }
    }

    # Appends the name of packages needed by other packages to the targeted list

    if ($Requires.IsPresent -or $Depends.IsPresent) {
        $count = $TargetedPackageList.Count;
        $index = 0;
        $targetedcount = 0;
        do {

            # Repeats this addition until no package is appended to the targeted list

            $count += $targetedcount;
            $targetedcount = 0;
            do {
                $packobj = $PackageMap.Item($TargetedPackageList.Item($index));
                $depnames = "";
                if ($packobj.($FIELD_DEPENDS) -ne $null) {
                    $depnames = $packobj.($FIELD_DEPENDS).Replace(' ', "");
                } elseif ($packobj.($FIELD_REQUIRES) -ne $null) {
                    $depnames = $packobj.($FIELD_REQUIRES).Replace(' ', ',');
                }
                if ($packobj.($FIELD_BUILD_DEPENDS) -ne $null) {
                    $depnames += ',' + $packobj.($FIELD_BUILD_DEPENDS).Replace(' ', "");
                }
                if ($depnames -ne "") {
                    $depnames.Split(',') | ForEach-Object {
                        $depname = $_ -replace $DEPENDED_PACKAGE_SUFFIX_EXPR, "";
                        $depobj = $PackageMap.Item($depname);
                        if ($depobj -ne $null) {  # The object of a package needed by others
                            if (-not $TargetedPackageList.Contains($depname)) {
                                $depobj.($FIELD_INSTALL_TARGETED) = $true;
                                [void]$TargetedPackageList.Add($depname);
                                $targetedcount++;
                            }
                        } elseif ($PackageProvidedSetMap -ne $null) {

                            # Adds all packages contained in the provided set of a name

                            $provset = $PackageProvidedSetMap.Item($depname);
                            if ($provset -ne $null) {
                                $provset | ForEach-Object {
                                    if (-not $TargetedPackageList.Contains($_)) {
                                        $depobj.($FIELD_INSTALL_TARGETED) = $true;
                                        [void]$TargetedPackageList.Add($_);
                                        $targetedcount++;
                                    }
                                }
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
        $packdownloaded = $DownloadParam -ne $null;
        if ($packdownloaded) {
            $DownloadParam.UrlBuilder.Length = 0;
            [void]$DownloadParam.UrlBuilder.Append($Mirror);
        }
    } `
    {
        $packobj = $PackageMap.Item($_);
        $instobj = $null;
        $srcobj = $null;

        # Creates the file object of a targeted package to output the information and/or download
        # binary and source files, and replaces the string with those in Install or Source field

        if ($packobj.($FIELD_INSTALL_TARGETED)) {
            $match = $packinstregex.Match($packobj.($FIELD_INSTALL));
            if ($match.Success) {
                $filepath = $match.Groups[1].Value;
                $size = [long]::Parse($match.Groups[6].Value);
                $hashvalue = $match.Groups[7].Value;
                $instobj = CreateFileObject $packdownloaded $filepath $size $hashvalue $STATE_NEW;
                $packobj.($FIELD_INSTALL) = $instobj;
            }
        }
        if ($packobj.($FIELD_SOURCE_TARGETED)) {
            $match = $packinstregex.Match($packobj.($FIELD_SOURCE));
            if ($match.Success) {
                $filepath = $match.Groups[1].Value;
                $size = [long]::Parse($match.Groups[6].Value);
                $hashvalue = $match.Groups[7].Value;
                $srcobj = CreateFileObject $packdownloaded $filepath $size $hashvalue $STATE_NEW;
                $packobj.($FIELD_SOURCE) = $srcobj;
            }
        }

        # Compares the version with the same package which has been installed on the local

        if (($localinstmap -ne $null) -and $localinstmap.Contains($_) -and ($instobj -ne $null)) {
            $verobj = GetCygwinVersion $packobj.($FIELD_VERSION);
            $result = CompareCygwinVersion $verobj $localinstmap.Item($_);
            if ($result -eq 0) {
                $instobj.($FIELD_STATE) = $STATE_UNCHANGED;
            } elseif ($result -lt 0) {
                $instobj.($FIELD_STATE) = $STATE_OLDER;
            }
        }
        if (($localsrcmap -ne $null) -and $localsrcmap.Contains($_) -and ($srcobj -ne $null)) {
            $verobj = GetCygwinVersion $packobj.($FIELD_VERSION);
            $result = CompareCygwinVersion $verobj $localsrcmap.Item($_);
            if ($result -eq 0) {
                $srcobj.($FIELD_STATE) = $STATE_UNCHANGED;
            } elseif ($result -lt 0) {
                $srcobj.($FIELD_STATE) = $STATE_OLDER;
            }
        }

        if ($packdownloaded) {

            # Downloads the package whose state is 'New' in its object from the mirror site

            if ($instobj -ne $null) {
                $DownloadParam.UrlBuilder.Length = $Mirror.Length;
                DownloadCygwinFile $instobj $DownloadParam;
            }
            if ($srcobj -ne $null) {
                $DownloadParam.UrlBuilder.Length = $Mirror.Length;
                DownloadCygwinFile $srcobj $DownloadParam;
            }
        }

        if ($packobj.($FIELD_VERSION_LABEL) -eq $null) {
            $packobj | Add-Member NoteProperty ($FIELD_VERSION_LABEL) $VERSION_LABEL_CURRENT;
        }
        Write-Output (SelectPackageInformation $packobj $SelectParam);
    }
} catch [System.Net.WebException] {
    $exception = $_.Exception;
    if ($exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
        Write-Error "'$Mirror' is not found" -Category InvalidArgument;
    } else {
        Write-Error -Exception $exception;
    }
    exit 1;
} catch [System.IO.IOException] {
    Write-Error -Exception $_.Exception;
    exit 1;
} finally {
    if ($reader -ne $null) {
        $reader.Close();
    }
    [System.IO.Directory]::SetCurrentDirectory($SystemDir);
    [Console]::CursorVisible = $ConsoleCursorVisible;
}
