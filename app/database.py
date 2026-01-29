# -*- coding: utf-8 -*-
"""
database.py
Database connection module for PostgreSQL.
"""

# built-in module imports
from typing import List, Dict, Any

# 3rd party module imports
import psycopg2

class DatabaseConnector:
    """PostgreSQL database connector using psycopg2.
    
    This class handles database connections and queries for retrieving
    sales data and product information.
    """
    
    def __init__(self, host: str, database: str, user: str, password: str,
                 port: int = 5432):
        """Initialize database connector with connection parameters.
        
        Args:
            host: Database host address.
            database: Database name.
            user: Database user name.
            password: Database password.
            port: Database port (default: 5432).
        """
        self.connection_params = {
            'host': host,
            'database': database,
            'user': user,
            'password': password,
            'port': port
        }
        self.connection = None
        
    def connect(self) -> None:
        """Establish connection to the database."""
        self.connection = psycopg2.connect(**self.connection_params)
        
    def disconnect(self) -> None:
        """Close database connection."""
        if self.connection:
            self.connection.close()
            self.connection = None
            
    def get_all_products(self) -> List[Dict[str, Any]]:
        """Retrieve all products from the products table.
        
        Returns:
            List of dictionaries containing product_id and product_name.
        """
        cursor = self.connection.cursor()
        cursor.execute("SELECT product_id, product_name FROM products")
        rows = cursor.fetchall()
        cursor.close()
        
        return [
            {'product_id': row[0], 'product_name': row[1]}
            for row in rows
        ]
        
    def get_sales_data(self, product_id: int) -> List[Dict[str, Any]]:
        """Retrieve sales data for a specific product.
        
        Args:
            product_id: The product ID to filter sales data.
            
        Returns:
            List of dictionaries containing date and sales values.
        """
        cursor = self.connection.cursor()
        query = """
            SELECT date, sales 
            FROM sales_data 
            WHERE product_id = %s 
            ORDER BY date
        """
        cursor.execute(query, (product_id,))
        rows = cursor.fetchall()
        cursor.close()
        
        return [
            {'date': row[0], 'sales': row[1]}
            for row in rows
        ]
