deb/
===============

This directory contains resources for 
building a .deb archive for webwork. 

`ns-control`
-------------

Currently the `ns-control` file is used
to generate a .deb to install the 
prerequisites of webwork available in the
Debian/Ubuntu software repositories.

To generate the `webwork_prerequisites-*.deb` 
archive do

`equivs-control ns-control`

Note that you must have the package `equivs`
installed to do this.

This is all very new and hasn't been tested 
much yet so use with caution.
