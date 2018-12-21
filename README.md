# gdrive - a Matlab class to simplify interaction with Google Drive.

This Matlab class relies on Petter Rasmussen's gdrive tool for all of the actual interaction with 
Google Drive, but wraps a Matlab class around it to make the interation a bit smoother. 

Some of the  gdrive executables are included, if you need a different one, please see [https://github.com/prasmussen/gdrive](https://github.com/prasmussen/gdrive)


Example
```Matlab
g=gdrive; % Connect to Google Drive (specify credentials as requested)
g.makeDir('/Test') % Make a directory called Test on Google Drive
g.put('filename','/Test') % Put the local file called filename into the /Test directory on Google drive.
```
