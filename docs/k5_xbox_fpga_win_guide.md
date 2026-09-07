

# K5-XBOX Acceleration Platform FPGA Environment

This project provide the guidelines for the K5-XBOX acceleration system FPGA Environment.

## Windows-11 installation prerequisites  
 
## Installing GIT for windows 

In case you don't have GIT on your windows system,
download and install "Git for windows"  [from here](https://gitforwindows.org/)  
I addition to git access this installation also provides a linux-like bash terminal on Windows which we will be using. Upon a successful installation  you should be able to shift-right-click at any windows explorer folder location and to select "open bash terminal here"

## Installing Python for Windows

In case you already  have python installed on your windows system, you need to verify it is on your environment settings path such that it can be invoked from a terminal.
The minimal requirement is that when you enter python from the git-bash terminal command line (git bash installation guided above) the indicated invoked python version will be 3.* (3.9.7 experienced to work well, highest released version presumably preferred) In case needed, you may easily Google to find guidelines on how to update windows path variables, 
however you need to know the path to your specific python installation to be added.

In case you don't have Python (version 3) on your windows system, download and install it.
We strongly recommend installing **Anaconda** which also include a complete Python version.
(such that you don't need to download many missing packages later)

In order to install Anaconda, carefully follow download and installation instructions
[from here](https://docs.anaconda.com/anaconda/install/windows/)
pay special attention to the specific guidance on adding Anaconda to your environment path.   
Alternatively tou may install [Miniconda](https://www.anaconda.com/docs/getting-started/miniconda/install) which is a lighter version of anaconda,
but you might be later requested to pip install some missing packages per requirements.

It is most-likely you are missing the pyserial package which we need for the UART connection, to resolve this run 

```bash
pip install pyserial  
```

## Installing Quartus minimal FPGA programming utility for Windows

Go to this [Quartus Download Page](https://www.intel.com/content/www/us/en/software-kit/849770/intel-quartus-prime-lite-edition-design-software-version-24-1-for-windows.html)

Scroll down the page to DOWNLOADS   
Click  tab: **individual files**
Scroll further down the page to:   
Last on the list of "Add-On and Stand-Alone Software" click to download:   
*Intel Quartus Prime Programmer and Tools 24.1std.0.1077*    
go to downloads folder, click the downloaded file to install   

If prompted respond as follow: 
allow app to make changes to device: YES  
Proceed by:
next->accept agreement ->next ... -> *default Installation folder C:\altera\24.1std*

Important: before finish DO NOT check any option, UN-CHECK all boxes includding "Launch USB blaster II drive installation" 
since this is NOT the correct USB-Blaster (FPGA programming cable interface) driver, instead click FINISH and follow below guidance. restart computer if requested.

## Setting up your Windows environment (Just Once)

Select a location on your windows system, we strongly recommend to avoid any spaces or non simple ascii characters in the path name (e.g. avoid Hebrew, Russian etc.) 
which tends to cause problems. We also recommend not to have the environment located at a cloud synchronized folder (e.g. dropbox, gdrive, onedrive) 
as big downloaded and intermediate generated files may be involved. A good location can be right at C:/Users/user/  
For your convenience you may create shortcut in windows desktop to that location.

At the selected location create a folder named
``` 
k5x_win
```
open a git-bash terminal at that folder location and perform following clone.  
for your information, in case of further updates in the environment you will be guided if needed to perform a git-pull

```bash
;# Run only once per installation from bash terminal at your k5x_win folder
 git clone https://gitlab.com/udik/k5_xbox_fpga_win.git
```
To build the environment (needed just once), run the following command.  
Note that this will also download a RISC-V C/C++ GCC compiler toolchain version if missing.  
This process may take a few minutes and requires approximately 1.3 GB of disk space.

```bash
source k5_xbox_fpga_win/setup/build_env.sh
```
## Updating the cloned repository

Currently, no action is required, as you have just cloned the latest version of the repository. However, if you receive a notification that the infrastructure has been updated, you may be asked to update your local repository. In that case, run the following commands in your laptop's bash terminal:

```bash
cd $K5X_WIN/k5_xbox_fpga_win
git pull
```


## Testing the toolchain

### Compiling hello_k5 example app SW
We can now test SW compilation of the famous hello_k5 example.   
Open a bash terminal (anywhere) and execute from it below commands
```bash
set_k5_terminal 
clear ;# This just clears the terminal (not mandatory)
launch_k5_app  hello_k5 -cmp   
```
Since -cmp is applied, only compilation is performed without proceeding to load and execute.   
Notice that in the FPGA environment we need only one terminal to run, because the simulation terminal is replaced to the physical FPGA board to be connected.  

Also be aware that in compile-only mode (-cmp), no success message is displayed. If no error messages are reported, the compilation completed successfully.

## Board Setup

After installing the Quartus Programmer, obtain the FPGA de10Lite Board and follow below steps. Ignore the "Download CD ..." sticker on the board. This provide a hint on how old this board is :smile: , ... old but faithful.

## Installing  USB-Blaster (FPGA programming cable) 

 connect the board using the USB-Blaster cable (the one included in the kit) as shown in the board picture fuerher below. Plug it into both the board and your laptop. Do not connect the other USB-UART cable at this stage.

The board should power up. On your laptop, open Device Manager (מנהל ההתקנים) and locate the Altera USB-Blaster, which may appear with a warning icon (indicating a driver issue).

Follow the steps shown in the chart below to install the correct driver.
Note: The chart was captured from a laptop using Hebrew user interface, but you should be able to follow along by identifying the corresponding steps in English if needed.

<img src="pics/install_usb_blaster_driver.png" alt="drawing" width="1000"  />  

## Installing the UART cable 
In addition to the USB cable, connect the UART cable  as in below pictures.  
connect the cables other USB side to your laptop/desktop directly or through a USB splitter if needed.


<img src="pics/de10Lite_k5_xboc_cables_connect.png" alt="drawing" width="500"  />  

**IMPORTANT:** Connect the USB-UART cable EXACTLY as in the picture:  
When you are facing the on-board text logos, connect the cable header to the outer pins row on the most right pins , green wire on the right and black wire on the left.  
By personal experience wrong connection can cause a permanent damage to the board.

## Transferring your application and accelerator FPGA bitstream to the environment

Download the desired FPGA bitstream .sof file generated on the cloud server, as described in the k5_xbox_gen_fpga_guide.pdf guide to be provided.  
Place the file at $FPGA_PROG_FILES which is a path variable to your built environment at k5x_win/my_k5_proj/fpga_prog_files

Additionally download your application sources and place them at $K5_SW_APPS/sudx    
you can download this by following the guidelines in previously provided document "Cloud files access..."  
on the cloud portal browse by "MY FILES" : to Desktop->k5_xbox_links/sudx   
then click button "Download all" , it will download the SW app files into a zip file on your laptop downloads.  
Copy the desired files to $K5_SW_APPS/sudx  (... k5x_win/my_k5_proj/sw/apps/sudx)

you also need to down load the shared enumerated types .svh file  
it is located on the cloud at : $MY_K5_PROJ/hw/xlrs/sudx/top/sudx_enums.svh   
download and place it on exact same path at $MY_K5_PROJ/hw/xlrs/sudx/top/sudx_enums.svh on your windows environment.



Generally, in order to display a pre-defined system variable expansion if interested, you can execute for example:
```bash
echo $FPGA_PROG_FILES
echo $K5_SW_APPS
```
Notice that the sources for below hello_k5 example are already available upon the build procedure.

## Programming the FPGA (Once per board power-up)
After connecting the cables and making sure your desired bitstream .sof is located at $FPGA_PROG_FILES/k5_xbox_<xlr_name>.sof
Notice that 
run from the terminal
the argument provide is your accelerator name as embedded in the .sof file name <xlr_name> in ddp26 case stands for sudx, however you might wish to keep several versions of it so you may rename for example to k5_xbox_sudx_v1.sof
sudx Example: 
```bash
prog_fpga sudx  
```
Upon a successful programming The 7Segment should display "**Hi ddP**"   
Incase of some JTAG related error message first-time after installation, try unplugging and plugging the cable to the board.

If you're still encountering a cable/JTAG-related error, try adding the following path to your Windows environment PATH variable:   
C:\altera\24.1std\qprogrammer\bin64  
(Thanks Avi Sinai for sharing)  


## Test the Board
After connecting the and programming the FPGA cables run from the terminal
```bash
set_k5_terminal
launch_k5_app hello_k5  
```
This should compile, load and execute the hello world application.  
If successful this message should print (among other messages)   
**HELLO K5, LETS GO**

## Potential Missing USB-UART cable driver
ONLY in case you get an error message regarding missing USB Serial or so, follow this provided guide to fix it.  
**Fixing_missing_USB_Serial_Port**  


## Potential Missing Python Packages

If you encounter an error message indicating that a package (e.g., `some_package_name`) is missing, it's likely due to a required Python package not being installed. You can easily resolve this by running the following command in your terminal:

```bash
pip install missing_package_name
```

If you have multiple versions of Python installed on your system, it's often more reliable to install the package using:

```bash
python -m pip install missing_package_name
```

Commonly reported missing packages include:

* `zmq`
* `pygame`
* `pyserial`
* `serial`
* `requests`

## Advanced optional flags are listed by:

```bash
set_k5_terminal 
launch_k5_app -h  
``` 
will list optional flags for some-non default values (nothing needed for now).   


## Running the sudx acceleration app

```bash
# SW only no acceleration
set_k5_terminal 
launch_k5_app sudx -asl $SUD_SHARED
# With pool and linear acceleration
launch_k5_app sudx -asl $SUD_SHARED -ccd1 LIN_XON -ccd2 POOL_XON
# once your conv accelerator is ready you can also add -ccd3 CONV_XON
# Notice applying "-ccd1 ALL_XON"  will enable al 3 accelerators.
```

## Speeding up your USB-UART connection for faster file access communication and printing.

You might notice that prints and file access appears somewhat slow and does not meet the performance expectations of FPGA emulation as compared to simulation. This is due to the default latency settings of the USB-UART cable's COM port.

To resolve this issue, open the Device Manager and follow these steps:
Ports (COM & LPT) → Right-click on the relevant COM port → Properties → Port Settings → Advanced → Set "Latency Timer (ms)" to 1. The specific COM port in use (e.g., COM3, COM4, etc.) is displayed in the terminal each time the application is launched.

<img src="pics/usb_ftdi_uart_latency_fix.png" alt="drawing" width="300"  />


Note that even with the speedup, the printing and file access remains the runtime bottleneck. If we prevent it, execution becomes orders of magnitude faster.

## Killing an hanging run
Just in case the application hangs for any reason (not responding for a while when expected) 
execute ctrl-C from the bash terminal.
if that does not help open another bash terminal and run there:

```bash
pkill_server
``` 
## Board Reset Button

For your information, the following chart indicates the assigned system hard reset button. However, it currently has no use, as an emulated hard reset is automatically triggered each time an application is launched.

<img src="pics/reset_button.png" alt="drawing" width="200"  />

