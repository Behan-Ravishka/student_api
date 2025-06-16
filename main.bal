import ballerina/http;
import ballerina/io;
import ballerina/uuid;

// --- TYPE DEFINITIONS ---
type Student record {
    string id;
    string name;
    int age;
    string course;
};

type StudentList Student[];

type NewStudent record {
    string name;
    int age;
    string course;
};

// --- MODULE-LEVEL STATE ---
Student[] studentList = [];
const string FILE_PATH = "students.json";

// --- CENTRALIZED RESPONSE HELPERS (THE PERMANENT SOLUTION) ---

function setCorsHeaders(http:Response res) {
    _ = res.setHeader("Access-Control-Allow-Origin", "*");
    _ = res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    _ = res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function sendJsonResponse(http:Caller caller, json payload, int statusCode = 200) returns error? {
    http:Response res = new;
    setCorsHeaders(res);
    res.statusCode = statusCode;
    res.setJsonPayload(payload);
    check caller->respond(res);
}

function sendTextResponse(http:Caller caller, string payload, int statusCode) returns error? {
    http:Response res = new;
    setCorsHeaders(res);
    res.statusCode = statusCode;
    res.setTextPayload(payload);
    check caller->respond(res);
}

// --- DATA PERSISTENCE FUNCTIONS ---
function saveToFile() returns error? {
    string content = studentList.toJsonString();
    check io:fileWriteString(FILE_PATH, content);
}

function loadFromFile() {
    var result = io:fileReadString(FILE_PATH);
    if result is string && result.trim().length() > 0 {
        var data = result.fromJsonString();
        if data is json {
            var typedResult = data.cloneWithType(StudentList);
            if typedResult is StudentList {
                studentList = typedResult;
            } else { io:println("WARN: Could not parse students.json into StudentList. ", typedResult.message()); }
        } else { io:println("WARN: Could not parse students.json as JSON. ", data.message()); }
    } else if result is error { io:println("WARN: Could not read students.json file. ", result.message()); }
}

// --- SERVICES ---

// Frontend service
service / on new http:Listener(7070) {
    resource function get .(http:Caller caller, http:Request req) returns error? {
        http:Response res = new;
        res.setTextPayload(check io:fileReadString("index.html"), contentType = "text/html");
        check caller->respond(res);
    }
}

// Backend API on port 7071
listener http:Listener studentsListener = new(7071);

service /students on studentsListener {

    resource function options [string... path](http:Caller caller, http:Request req) returns error? {
        check sendTextResponse(caller, "", 200);
    }

    resource function get list(http:Caller caller, http:Request req) returns error? {
        check sendJsonResponse(caller, <json>studentList);
    }

    resource function post register(http:Caller caller, http:Request req) returns error? {
        do {
            json payload = check req.getJsonPayload();
            NewStudent newStudentData = check payload.cloneWithType();
            Student newStudent = {
                id: uuid:createType4AsString(),
                name: newStudentData.name,
                age: newStudentData.age,
                course: newStudentData.course
            };
            studentList.push(newStudent);
            check saveToFile();
            check sendJsonResponse(caller, <json>newStudent, 201);
        } on fail error err {
            io:println("ERROR during registration: ", err);
            check sendTextResponse(caller, "❌ Invalid request: " + err.message(), 400);
        }
    }

    resource function put update/[string id](http:Caller caller, http:Request req) returns error? {
        int? foundIndex = ();
        foreach int i in 0 ..< studentList.length() {
            if studentList[i].id == id {
                foundIndex = i;
                break;
            }
        }
        if foundIndex is () {
            check sendTextResponse(caller, "❌ Student not found", 404);
            return;
        }

        do {
            json payload = check req.getJsonPayload();
            Student updatedData = check payload.cloneWithType();
            studentList[foundIndex] = updatedData;
            check saveToFile();
            check sendJsonResponse(caller, <json>updatedData, 200);
        } on fail error err {
            io:println("ERROR during update: ", err);
            check sendTextResponse(caller, "❌ Invalid update data: " + err.message(), 400);
        }
    }

    // --- MODIFIED AND PERFECTED DELETE FUNCTION ---
    resource function delete delete/[string id](http:Caller caller, http:Request req) returns error? {
        do {
            // Step 1: Find the student
            int? foundIndex = ();
            foreach int i in 0 ..< studentList.length() {
                if studentList[i].id == id {
                    foundIndex = i;
                    break;
                }
            }

            // Step 2: Handle the "not found" case gracefully
            if foundIndex is () {
                check sendTextResponse(caller, "❌ Student not found", 404);
                return; // Exit the function successfully after responding
            }

            // Step 3: If found, remove and save. A failure here will be caught.
            _ = studentList.remove(foundIndex);
            check saveToFile(); // If this fails, the 'on fail' block will catch it.

            // Step 4: If all steps above succeed, send the success response.
            check sendTextResponse(caller, "🗑️ Student deleted successfully", 200);

        } on fail error err {
            // This is the master safety net. ANY `check` failure in the `do` block
            // (e.g., file system error, closed connection) will end up here.
            io:println("FATAL ERROR during delete: ", err);
            // We guarantee a response with CORS headers is sent no matter what.
            check sendTextResponse(caller, "❌ A server error occurred during deletion.", 500);
        }
    }
}

public function main() returns error? {
    loadFromFile();
    io:println("✅ Student API backend started on http://localhost:7071");
    io:println("✅ Frontend service started on http://localhost:7070");
}