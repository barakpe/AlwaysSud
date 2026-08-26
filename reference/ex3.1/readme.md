
## Getting started

Set up your workspace and pull in the base project:

```sh
tsmc65
git clone https://github.com/DDP26-summer/ex3.1
cp -r ex3.1/my_k5_proj_ref/hw my_k5_proj
cp -r ex3.1/my_k5_proj_ref/sw my_k5_proj
```

## Running scan simulation

**Terminal 1 — start the simulator**

```sh
set_k5_terminal
launch_k5_sim sudx_scan
```

**Terminal 2 — launch the application**

```sh
set_k5_terminal
launch_k5_app sudx_scan  -asl sud_shared  -gpv 51blanks
```
