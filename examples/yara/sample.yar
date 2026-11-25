rule EtmacsExample
{
    meta:
        author = "Etmacs"
        description = "Small rule for YARA editing and LSP checks"

    strings:
        $marker = "ETMACS_EXAMPLE" ascii wide
        $hex = { 45 54 4D 41 43 53 }

    condition:
        any of them
}
