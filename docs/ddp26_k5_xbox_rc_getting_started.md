

## Initial Setup
In your BIU-Engineering cloud environment open a terminal anywhere and enter the following command:
source /project/tsmc65/shared/k5_share/k5_xbox/setup/build_k5_proj_rc3.sh
This only needs to be executed once ever, and should take just a few seconds. It will permanently configure
your account setup for the environment.
Once the setup is complete, close the terminal and open a new one to continue with the next steps !
Your personal working environment
Running above setup script automatically generate following folder in your tsmc65 workspace, go into it by:
tsmc65
cd $ws/my_k5_proj
ls -l
You will find there three sub-folders:
sw, For software applications.
hw, For hardware accelerators.
sim, For simulation workspace.
tmp_backups, Used for some temporary backups (ignore)
"Running Hello K5" application example (Software only)
The setup script already copied over some reference application and acceleration examples.
View the hello_k5 example application C source code by opening it with your preferred editor (for example
vscode) as follow:
code $MY_K5_PROJ/sw/apps/hello_k5/hello_k5.c
To run our SOC SW application in simulation we need to open two terminal sessions:
Terminal-1, Software application User Interface.
Terminal-2, Hardware Verilog Simulation for SOC platform and acceleration logic.
The two terminal sessions will invisibly communicate one with the other as demonstrated bellow.
Open two separate terminals and in each of them run the same following command.

set_k5_terminal
In one of the two terminals (doesn't matter which) start the application by:
launch_k5_app hello_k5
In the other terminal start the simulation session by:
launch_k5_sim
The two terminal sessions will wait each for the other and will proceed to simulation once both are started.
The prints from the application C code will show up on the application launching terminal. See below
Troubleshooting section in case of a reported missing Python Packages
Creating your own software application.
Now lets create a new application named hello_me We need to create an app folder per application, lets start
based on hello_k5 example by:
mkdir -p $MY_K5_PROJ/sw/apps/hello_me
cp $MY_K5_PROJ/sw/apps/hello_k5/hello_k5.c $MY_K5_PROJ/sw/apps/hello_me/hello_me.c
cp $MY_K5_PROJ/sw/apps/hello_k5/k5_example_in.txt $MY_K5_PROJ/sw/apps/hello_me/
Edit and make some minor changes to your application such as changing the greeting message, and possibly
also in the application accessed input text file. For example by the vscode editor as follow:
code $MY_K5_PROJ/sw/apps/hello_me/hello_me.c
code $MY_K5_PROJ/sw/apps/hello_me/k5_example_in.txt
Run the application as described in above example, replace 'hello_k5' in the launch commands to 'hello_me'
Make sure the application terminal, respond according to your modifications.
## Troubleshooting
## Potential Missing Python Packages
Only if you encounter an error message indicating that a package (e.g., some_package_name) is missing (such
as zmq, serial, pyserial), it's likely due to a required Python package not being installed. You can resolve this by
running one of the following command in your terminal,

python -m pip install missing_package_name
ONLY in case above command does not work, try one of the following in the given order, what ever works
first.
pip install missing_package_name
pip3.9 install missing_package_name
pip3 install missing_package_name
pip3.9 install --user missing_package_name