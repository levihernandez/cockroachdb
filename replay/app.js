// List dir contents: https://medium.com/stackfame/get-list-of-all-files-in-a-directory-in-node-js-befd31677ec5



var express = require("express");
var app = express();
var router = express.Router();
var path = __dirname + '/views/';

// Constants
const PORT = 8081;
const HOST = '0.0.0.0';


//requiring path and fs modules
const cast_path = require('path');
const fs = require('fs');
//joining path of directory 
const directoryPath = cast_path.join(__dirname, 'casts');
//passsing directoryPath and callback function
fs.readdir(directoryPath, function (err, files) {
    //handling error
    if (err) {
        return console.log('Unable to scan directory: ' + err);
    } 

    //listing all files using forEach
    files.forEach(function (file) {
        // Do whatever you want to do with the file
        console.log(file); 
    });
});



router.use(function (req,res,next) {
  console.log("/" + req.method);
  next();
});

router.get("/",function(req,res){
  res.sendFile(path + "index.html");
});

app.use(express.static(__dirname + '/public'));
app.use(express.static(__dirname + '/casts'));

app.use(express.static(path));
app.use("/", router);

app.listen(8081, function () {
  console.log('App is listening on port 8081!')
})
