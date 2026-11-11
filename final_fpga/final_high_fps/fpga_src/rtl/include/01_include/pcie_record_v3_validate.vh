// Include inside each transport owner. Checks the frozen sparse wire structure;
// numerical validity remains the actual producer's status, never inferred here.
function sparse_v3_valid;
    input [2047:0] value;
    begin
        sparse_v3_valid=value[31:0]==`PCIE_RECORD_V3_SPARSE_MAGIC &&
            value[39:32]==`PCIE_RECORD_V3_SPARSE_SCHEMA && value[47:40]==`PCIE_RECORD_V3_STRIPS &&
            value[55:52]==value[51:48] && value[127:57]==0 && value[2047:2001]==0 &&
            (!(|value[51:49]) || value[48]) &&
            (value[48] || value[651:128]==0) &&
            (value[49] || value[1847:652]==0) &&
            (value[50] || value[1895:1848]==0) &&
            (value[51] || value[2000:1896]==0);
    end
endfunction
