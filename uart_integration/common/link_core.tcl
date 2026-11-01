# Links both AES-GCM cores into the open Libero project. Needs REPO and common:
# build_12m.tcl and build_spi.tcl source it.

# Files the project may already link are skipped: the build fails if one is really missing.
proc link_hdl {path} { catch {create_links -hdl_source $path} }

foreach key_bits {256 128} {
    set stream [open $common/aes${key_bits}_core_files.f]
    foreach line [split [read $stream] "\n"] {
        # Identical to RTL/Key_Expansion_256/SubWord.sv: one module name can only be linked once
        if {$line eq "RTL/AES-CTR/Key_Expansion/GFunction/SubWord.sv"} { continue }
        if {$line ne "" && ![string match "//*" $line]} { link_hdl $REPO/$line }
    }
    close $stream
}
