# Links both AES-GCM cores into the open Libero project and defines what the build_*.tcl
# scripts share. Needs REPO and common, which those scripts set before sourcing this file.

# Files the project may already link are skipped: the build fails if one is really missing.
proc link_hdl {path} { catch {create_links -hdl_source $path} }

proc link_constraints {sdc pdc} {
    catch {create_links -sdc $sdc}
    catch {create_links -io_pdc $pdc}
}

# Builds one Design Root through Verify Timing. Libero keeps results per root.
proc build_root {top sdc pdc} {
    set_root -module $top
    foreach tool {SYNTHESIZE VERIFYTIMING} {
        organize_tool_files -tool $tool -file $sdc -module $top -input_type {constraint}
    }
    organize_tool_files -tool {PLACEROUTE} -file $sdc -file $pdc -module $top -input_type {constraint}

    run_tool -name {SYNTHESIZE}
    run_tool -name {PLACEROUTE}
    run_tool -name {VERIFYTIMING}
    save_project
}

foreach key_bits {256 128} {
    set stream [open $common/aes${key_bits}_core_files.f]
    foreach line [split [read $stream] "\n"] {
        # Identical to RTL/Key_Expansion_256/SubWord.sv: one module name can only be linked once
        if {$line eq "RTL/AES-CTR/Key_Expansion/GFunction/SubWord.sv"} { continue }
        if {$line ne "" && ![string match "//*" $line]} { link_hdl $REPO/$line }
    }
    close $stream
}
