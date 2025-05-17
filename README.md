extract-cygwin
===============

Cygwin installer displays the name, version, and description of packages on
the wizard, reading those information from `setup.ini`, and can download
packages for your sellection from the mirror site.

This script will extract the information of Cygwin packages from `setup.ini`
and download that package's file to the local installation directory,
which works with Powershell 2.0 and later.

## Usage

The package information of which target names are specified with `-Package`,
`-PackageSet`, and/or `-Category` is extracted, led by `x86` or `x86_64` for
32-bit or 64-bit architecture. In addition to that, the information of packages
needed by others is extracted with `-Depends` or `-Requires`.

To extract the information of 32-bit cygwin and git package:

    .\Extract-Cygwin.ps1 x86 -Package cygwin, git

With `-Download`, the package's file in the directory described on that
information is downloaded to the local from the mirror site of URL specified
with `-Mirror` or the country of the cuurent region if present.

Run the following command if you wish to use 64-bit packages of `Base`
category, download that files:

<p>
  <img alt="Download" src="https://github.com/kawagita/extract-cygwin/raw/master/download.gif"/>
</p>

To display the detailed information about this script:

    man .\Extract-Cygwin.ps1 -Detailed

## Note

Extracting the information of Cygwin 32-bit or 64-bit package requires
`setup.ini` on `x86` or `x86_64` directory. However, this script can download
Cygwin installer and `setup.ini` with `-Download`.

Run the following line if any scripts can not be executed on your system:

    Set-ExecutionPolicy RemoteSigned -Scope Process

## License

This script is published under the MIT License.
