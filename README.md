# Faasm-Sledge-Battle-of-Speed-and-Scale
This is a benchmarking framework created in an effort to benchmark wasm frameworks &amp; help researchers verify the results made in Research.
The scope of this project, was to benchmarks the FAASM and Sledge webassembly frameworks.

----------
Functions tested on Sledge & Faasm:
  No-op (Do nothing)
  Fibonacci of 25 (Compute Intensive)
  Html 720KB (Network data intensive)
----------
Refer the ppt for summarize of out conclusion. 
Refer the sub directories for records of all the graphs/benchmarks pertaining to memory,CPU usage that were generated as part of our experiments.


Inspiration

The task was to do some meaningful work in the field of cloud computing. 
And we stumbled across an initiative being done by a Graduate Student in field of Web Assembly. 

That's were our project helped him complete a piece of his Master projects and for us it for a coursework project. 
Overall, the project was demanding as web assembly is definitely a niche, and uncommon technology. 

---

<h1> What is WebAssembly?
</h1>
<p>“WebAssembly (abbreviated Wasm) is a binary instruction format for a stack-based virtual machine.”
 
Wasm is designed as a portable compilation target for programming languages, enabling deployment on the web for client and server applications.
</p>

<img width="1123" alt="Screenshot 2023-12-27 at 5 04 35 PM" src="https://github.com/mmaashraf/Faasm-Sledge-Battle-of-Speed-and-Scale/assets/37049007/1c720504-7042-4929-94a1-44e97eb6f47f">

<h1>Web Assembly Language support & its usage in contempory times</h1>

<p>

  WebAssembly runs in all major browsers and in all platforms. Developers can reasonably assume WebAssembly support is anywhere JavaScript is available.
With around 40 languages that can compile to WebAssembly, developers can finally use their favorite language on the Web.
WebAssembly has been successfully deployed in the real world, too:
eBay implemented a universal barcode scanner.
Google Earth can run in any browser now, thanks to WebAssembly.
The Doom 3 engine has also been ported to WebAssembly. You can play the demo online.
Autodesk ported AutoCad to web browsers using WebAssembly.

Source: https://www.stackpath.com/


</p>
<img width="1198" alt="Screenshot 2023-12-27 at 5 06 15 PM" src="https://github.com/mmaashraf/Faasm-Sledge-Battle-of-Speed-and-Scale/assets/37049007/6fb57b63-17b1-482e-b5d3-280d4fa57cab">




<h1>
Wasm future
</h1>
<p>
Compile once, run anywhere
Mix and match “component” tools of any language
Secure monolithic applications with plug-ins
Serverless & FaaS
  
</p>

<h1> WASM</h1>
<p>
Current solution: Docker containers
Isolation overhead - ~100s milliseconds latency for containers
Relatively large memory footprint
Inefficient state sharing between containers
WebAssembly
Safety guarantee via software fault isolation
Memory isolation with per process contiguous memory block allocation
Problems to solve:
Lessen memory restrictions for state sharing
Provide interface for OS operations
Standardized orchestration

</p>

<h1>What are we evaluating?</h1>

<p>


Metrics:-
CPU Utilisation, Cycles
Memory Footprint
Start-up times

Platforms:-
Wasm Flavours (Sledge, Faasm, Wasmtime*).
Existing serverless technologies (SPRIGHT & Knative). 

</p>
