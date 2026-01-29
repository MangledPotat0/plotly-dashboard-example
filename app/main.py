# -*- coding: utf-8 -*-
"""
main.py
Main Flask application for sales dashboard.
"""

# built-in module imports
import os

# 3rd party module imports
from flask import Flask, render_template_string

# local module imports
from app.database import DatabaseConnector
from app.visualization import create_interactive_dashboard

app = Flask(__name__)

@app.route('/')
def index():
    """Render the sales dashboard home page.
    
    Returns:
        Rendered HTML page with interactive Plotly visualization.
    """
    db_host = os.getenv('DB_HOST', 'localhost')
    db_name = os.getenv('DB_NAME', 'sales_db')
    db_user = os.getenv('DB_USER', 'postgres')
    db_password = os.getenv('DB_PASSWORD', 'password')
    
    db = DatabaseConnector(db_host, db_name, db_user, db_password)
    db.connect()
    
    try:
        products = db.get_all_products()
        dashboard_html = create_interactive_dashboard(products, db)
        
        html_template = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Sales Dashboard</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    margin: 20px;
                    background-color: #f5f5f5;
                }
                h1 {
                    color: #333;
                    text-align: center;
                }
                .container {
                    max-width: 1200px;
                    margin: 0 auto;
                    background-color: white;
                    padding: 20px;
                    border-radius: 8px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Sales Dashboard</h1>
                {{ dashboard_html|safe }}
            </div>
        </body>
        </html>
        """
        
        return render_template_string(html_template, 
                                       dashboard_html=dashboard_html)
    finally:
        db.disconnect()


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
