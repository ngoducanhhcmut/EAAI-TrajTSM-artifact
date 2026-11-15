#!/bin/bash
for p in $(pgrep -f 'Vtb_tsmx_chain'); do [ "$p" != "$$" ] && kill $p; done
for p in $(pgrep -f 'vl_chain.sh|vl_chain2.sh'); do [ "$p" != "$$" ] && kill $p; done
sleep 2; echo "left: $(pgrep -fc Vtb_tsmx_chain)"
