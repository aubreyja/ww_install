#!/usr/bin/env perl

use strict;
use warnings;

use RedHat;

foreach(keys %{$RedHat::prerequisites}) {
  print "$_\n";
}
