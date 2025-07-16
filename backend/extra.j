require('dotenv').config();
const express = require("express");
const multer = require("multer");
const path = require("path");
const { Pool } = require("pg");
const cors = require("cors");
const fs = require("fs");
const mime = require('mime-types');

const app = express();
const PORT = process.env.PORT || 3408;

// CORS Setup
app.use(cors({
  origin: [
    process.env.FRONTEND_URL,
    "http://13.48.203.134:8029",
    "http://13.48.203.134:3408",
    "http://13.48.203.134:5500",
    "http://13.48.203.134:5500",
    "http://13.48.203.134:8030",
    "http://employee-frontend:80",
    "http://hr-frontend:80"
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// File upload setup
const uploadDir = path.join(__dirname, "uploads");
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}
app.use('/uploads', express.static(uploadDir));

// PostgreSQL Pool Configuration
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'postgres-db',
  database: process.env.DB_NAME || 'onboarding',
  password: process.env.DB_PASSWORD || 'admin123',
  port: process.env.DB_PORT || 5432,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// Error handling for the pool
pool.on('error', (err) => {
  console.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Connect to DB
const connectToDatabase = async (retries = 5, delay = 5000) => {
  let client;
  try {
    client = await pool.connect();
    console.log("Connected to PostgreSQL");
  } catch (err) {
    console.error("DB connection error:", err);
    if (retries > 0) {
      console.log(`Retrying connection (${retries} attempts left)...`);
      setTimeout(() => connectToDatabase(retries - 1, delay), delay);
    } else {
      console.error("Max retries reached. Exiting...");
      process.exit(1);
    }
  } finally {
    if (client) client.release();
  }
};
connectToDatabase();

// Multer Storage
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    cb(null, Date.now() + '-' + Math.round(Math.random() * 1E9) + path.extname(file.originalname));
  }
});

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => {
    const allowedTypes = [
      'application/pdf', 'image/jpeg', 'image/png',
      'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'text/plain', 'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    ];
    if (!allowedTypes.includes(file.mimetype)) {
      return cb(new Error(`Invalid file type: ${file.mimetype}`));
    }
    cb(null, true);
  },
  limits: { fileSize: 5 * 1024 * 1024 }
});

// File Cleanup
const cleanupFiles = (files) => {
  if (!files) return;
  Object.values(files).forEach(fileArray => {
    fileArray.forEach(file => {
      try {
        const filePath = path.join(uploadDir, file.filename);
        if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
      } catch (err) {
        console.error("File cleanup error:", err);
      }
    });
  });
};

// Error Handling Middleware
app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    return res.status(400).json({ error: err.message, code: 'UPLOAD_ERROR' });
  } else if (err) {
    return res.status(500).json({ error: err.message, code: 'SERVER_ERROR' });
  }
  next();
});

// Save Employee Endpoint
app.post("/save-employee", upload.fields([
  { name: "emp_profile_pic", maxCount: 1 },
  { name: "emp_salary_slip", maxCount: 1 },
  { name: "emp_offer_letter", maxCount: 1 },
  { name: "emp_relieving_letter", maxCount: 1 },
  { name: "emp_experience_certificate", maxCount: 1 },
  { name: "emp_ssc_doc", maxCount: 1 },
  { name: "emp_inter_doc", maxCount: 1 },
  { name: "emp_grad_doc", maxCount: 1 },
  { name: "resume", maxCount: 1 },
  { name: "id_proof", maxCount: 1 },
  { name: "signed_document", maxCount: 1 }
]), async (req, res) => {
  const client = await pool.connect();
  try {
    const result = await client.query(`
      INSERT INTO ajay_table (
        emp_name, emp_email, emp_gender, emp_marital_status, emp_dob, emp_mobile,
        emp_address, emp_city, emp_state, emp_zipcode, emp_bank, emp_account,
        emp_ifsc, emp_bank_branch, emp_job_role, emp_department, emp_experience_status,
        emp_company_name, emp_years_of_experience, emp_joining_date, emp_profile_pic,
        emp_salary_slip, emp_offer_letter, emp_relieving_letter, emp_experience_certificate,
        emp_ssc_doc, ssc_school, ssc_year, ssc_grade, emp_inter_doc, inter_college,
        inter_year, inter_grade, inter_branch, emp_grad_doc, grad_college, grad_year,
        grad_grade, grad_degree, grad_branch, resume, id_proof, signed_document,
        primary_contact_name, primary_contact_relationship, primary_contact_phone,
        primary_contact_email, uan_number, pf_number, emp_terms_accepted
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
        $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
        $21, $22, $23, $24, $25, $26, $27, $28, $29, $30,
        $31, $32, $33, $34, $35, $36, $37, $38, $39, $40,
        $41, $42, $43, $44, $45, $46, $47, $48, $49, $50
      )
      RETURNING id
    `, [
      req.body.emp_name,
      req.body.emp_email,
      req.body.emp_gender || null,
      req.body.emp_marital_status || null,
      req.body.emp_dob || null,
      req.body.emp_mobile || null,
      req.body.emp_address || null,
      req.body.emp_city || null,
      req.body.emp_state || null,
      req.body.emp_zipcode || null,
      req.body.emp_bank || null,
      req.body.emp_account || null,
      req.body.emp_ifsc || null,
      req.body.emp_bank_branch || null,
      req.body.emp_job_role || null,
      req.body.emp_department || null,
      req.body.emp_experience_status || null,
      req.body.emp_company_name || null,
      req.body.emp_years_of_experience ? parseInt(req.body.emp_years_of_experience) : null,
      req.body.emp_joining_date || null,
      req.files["emp_profile_pic"]?.[0]?.filename || null,
      req.files["emp_salary_slip"]?.[0]?.filename || null,
      req.files["emp_offer_letter"]?.[0]?.filename || null,
      req.files["emp_relieving_letter"]?.[0]?.filename || null,
      req.files["emp_experience_certificate"]?.[0]?.filename || null,
      req.files["emp_ssc_doc"]?.[0]?.filename || null,
      req.body.ssc_school || null,
      req.body.ssc_year ? parseInt(req.body.ssc_year) : null,
      req.body.ssc_grade || null,
      req.files["emp_inter_doc"]?.[0]?.filename || null,
      req.body.inter_college || null,
      req.body.inter_year ? parseInt(req.body.inter_year) : null,
      req.body.inter_grade || null,
      req.body.inter_branch || null,
      req.files["emp_grad_doc"]?.[0]?.filename || null,
      req.body.grad_college || null,
      req.body.grad_year ? parseInt(req.body.grad_year) : null,
      req.body.grad_grade || null,
      req.body.grad_degree || null,
      req.body.grad_branch || null,
      req.files["resume"]?.[0]?.filename || null,
      req.files["id_proof"]?.[0]?.filename || null,
      req.files["signed_document"]?.[0]?.filename || null,
      req.body.primary_contact_name || null,
      req.body.primary_contact_relationship || null,
      req.body.primary_contact_phone || null,
      req.body.primary_contact_email || null,
      req.body.uan_number || null,
      req.body.pf_number || null,
      req.body.emp_terms_accepted || false
    ]);

    res.status(201).json({ success: true, employeeId: result.rows[0].id });
  } catch (err) {
    cleanupFiles(req.files);
    console.error("Save employee error:", err);
    if (err.code === '23505' && err.constraint === 'ajay_table_emp_email_key') {
      return res.status(400).json({ error: "Email already exists" });
    }
    res.status(500).json({ error: "Database error" });
  } finally {
    client.release();
  }
});

// Get all employees with document URLs
app.get("/employees", async (req, res) => {
  const client = await pool.connect();
  try {
    const result = await client.query("SELECT * FROM ajay_table ORDER BY created_at DESC");
    const employees = result.rows.map(emp => {
      const employeeData = { ...emp };

      const documentFields = [
        'emp_profile_pic', 'emp_salary_slip', 'emp_offer_letter',
        'emp_relieving_letter', 'emp_experience_certificate', 'emp_ssc_doc',
        'emp_inter_doc', 'emp_grad_doc', 'resume',
        'id_proof', 'signed_document'
      ];

      documentFields.forEach(field => {
        if (employeeData[field]) {
          employeeData[`${field}_url`] = `${req.protocol}://${req.get('host')}/uploads/${employeeData[field]}`;
        }
      });

      return employeeData;
    });

    res.json(employees);
  } catch (error) {
    console.error("Fetch employees error:", error);
    res.status(500).json({ error: "Database error" });
  } finally {
    client.release();
  }
});

// Get single employee by ID with full details
app.get("/employees/:id", async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const result = await client.query("SELECT * FROM ajay_table WHERE id = $1", [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Employee not found" });
    }

    const employee = result.rows[0];
    const employeeData = { ...employee };

    const documentFields = [
      'emp_profile_pic', 'emp_salary_slip', 'emp_offer_letter',
      'emp_relieving_letter', 'emp_experience_certificate', 'emp_ssc_doc',
      'emp_inter_doc', 'emp_grad_doc', 'resume',
      'id_proof', 'signed_document'
    ];

    documentFields.forEach(field => {
      if (employeeData[field]) {
        employeeData[`${field}_url`] = `${req.protocol}://${req.get('host')}/uploads/${employeeData[field]}`;
      }
    });

    res.json(employeeData);
  } catch (error) {
    console.error("Fetch employee error:", error);
    res.status(500).json({ error: "Database error" });
  } finally {
    client.release();
  }
});

// Get document URLs for an employee
app.post("/get-documents", async (req, res) => {
  const client = await pool.connect();
  try {
    const { empEmail } = req.body;
    if (!empEmail) {
      return res.status(400).json({ error: "Employee email is required" });
    }

    const result = await client.query(
      "SELECT * FROM ajay_table WHERE emp_email = $1",
      [empEmail]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Employee not found" });
    }

    const employee = result.rows[0];
    const documents = {};

    const docFields = [
      { field: 'emp_profile_pic', name: 'Profile Picture' },
      { field: 'emp_salary_slip', name: 'Salary Slip' },
      { field: 'emp_offer_letter', name: 'Offer Letter' },
      { field: 'emp_relieving_letter', name: 'Relieving Letter' },
      { field: 'emp_experience_certificate', name: 'Experience Certificate' },
      { field: 'emp_ssc_doc', name: 'SSC Document' },
      { field: 'emp_inter_doc', name: 'Intermediate Document' },
      { field: 'emp_grad_doc', name: 'Graduation Document' },
      { field: 'resume', name: 'Resume' },
      { field: 'id_proof', name: 'ID Proof' },
      { field: 'signed_document', name: 'Signed Document' }
    ];

    docFields.forEach(({field, name}) => {
      if (employee[field]) {
        documents[field] = {
          url: `${req.protocol}://${req.get('host')}/uploads/${employee[field]}`,
          name:employee[field],
          filename: employee[field]
        };
      }
    });

    res.json({ documents });
  } catch (error) {
    console.error("Get documents error:", error);
    res.status(500).json({ error: "Server error while fetching documents" });
  } finally {
    client.release();
  }
});

// Download single document
app.get("/download/:filename", (req, res) => {
  try {
    const { filename } = req.params;
    const filePath = path.join(uploadDir, filename);

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: "File not found" });
    }

    const mimeType = mime.lookup(filePath) || 'application/octet-stream';
    res.setHeader('Content-Type', mimeType);
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    fs.createReadStream(filePath).pipe(res);
  } catch (err) {
    console.error("File download error:", err);
    res.status(500).json({ error: "Error while downloading file" });
  }
});

// Pool status endpoint (for monitoring)
app.get("/pool-status", async (req, res) => {
  try {
    const poolStatus = {
      totalCount: pool.totalCount,
      idleCount: pool.idleCount,
      waitingCount: pool.waitingCount
    };
    res.json(poolStatus);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Start server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

// Graceful shutdown
process.on('SIGINT', async () => {
  await pool.end();
  process.exit(0);
});
