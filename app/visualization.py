# -*- coding: utf-8 -*-
"""
app/visualization.py
Plotly visualization module for sales data.
"""

from typing import List, Dict, Any

import plotly.graph_objects as go


def create_sales_plot(sales_data: List[Dict[str, Any]], 
                      product_name: str) -> go.Figure:
    """Create an interactive Plotly line chart for cumulative sales data.
    
    Args:
        sales_data: List of dictionaries with 'date' and 'sales' keys.
        product_name: Name of the product for the chart title.
        
    Returns:
        Plotly Figure object.
    """
    dates = [item['date'] for item in sales_data]
    sales = [item['sales'] for item in sales_data]
    
    # Calculate cumulative sales
    cumulative_sales = []
    running_total = 0
    for sale in sales:
        running_total += sale
        cumulative_sales.append(running_total)
    
    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=dates,
        y=cumulative_sales,
        mode='lines+markers',
        name='Cumulative Sales',
        line=dict(color='#2ca02c', width=2),
        marker=dict(size=8),
        fill='tozeroy',
        fillcolor='rgba(44, 160, 44, 0.1)'
    ))
    
    fig.update_layout(
        title=f'Cumulative Sales Over Time - {product_name}',
        xaxis_title='Date',
        yaxis_title='Cumulative Sales ($)',
        hovermode='x unified',
        template='plotly_white',
        font=dict(size=12),
        height=500
    )
    
    return fig


def create_interactive_dashboard(products: List[Dict[str, Any]], 
                                  db_connector) -> str:
    """Create interactive dashboard HTML with product dropdown.
    
    Args:
        products: List of product dictionaries.
        db_connector: Database connector instance.
        
    Returns:
        HTML string containing the interactive dashboard.
    """
    if not products:
        return "<p>No products available</p>"
    
    first_product = products[0]
    sales_data = db_connector.get_sales_data(first_product['product_id'])
    fig = create_sales_plot(sales_data, first_product['product_name'])
    
    buttons = []
    for product in products:
        product_sales = db_connector.get_sales_data(product['product_id'])
        dates = [item['date'] for item in product_sales]
        sales = [item['sales'] for item in product_sales]
        
        # Calculate cumulative sales for dropdown
        cumulative_sales = []
        running_total = 0
        for sale in sales:
            running_total += sale
            cumulative_sales.append(running_total)
        
        buttons.append(
            dict(
                label=product['product_name'],
                method='update',
                args=[
                    {'x': [dates], 'y': [cumulative_sales]},
                    {'title': f"Cumulative Sales Over Time - {product['product_name']}"}
                ]
            )
        )
    
    fig.update_layout(
        updatemenus=[
            dict(
                buttons=buttons,
                direction='down',
                showactive=True,
                x=0.17,
                xanchor='left',
                y=1.15,
                yanchor='top'
            )
        ]
    )
    
    return fig.to_html(include_plotlyjs='cdn', div_id='sales-plot')
