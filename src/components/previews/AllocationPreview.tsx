import { useState } from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Sector } from 'recharts';

const data = [
    { name: 'Stocks', value: 55, color: '#3b82f6' },
    { name: 'Crypto', value: 25, color: '#8b5cf6' },
    { name: 'Real Estate', value: 15, color: '#10b981' },
    { name: 'Cash', value: 5, color: '#f59e0b' },
];

const renderActiveShape = (props: any) => {
    const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill, payload, value } = props;

    return (
        <g>
            <text x={cx} y={cy} dy={-10} textAnchor="middle" fill="#fff" className="text-lg font-bold">
                {payload.name}
            </text>
            <text x={cx} y={cy} dy={15} textAnchor="middle" fill="#9ca3af" className="text-sm">
                {`${value}%`}
            </text>
            <Sector
                cx={cx}
                cy={cy}
                innerRadius={innerRadius}
                outerRadius={outerRadius + 8}
                startAngle={startAngle}
                endAngle={endAngle}
                fill={fill}
            />
            <Sector
                cx={cx}
                cy={cy}
                startAngle={startAngle}
                endAngle={endAngle}
                innerRadius={outerRadius + 12}
                outerRadius={outerRadius + 14}
                fill={fill}
            />
        </g>
    );
};

export const AllocationPreview = () => {
    const [activeIndex, setActiveIndex] = useState(0);

    const onPieEnter = (_: any, index: number) => {
        setActiveIndex(index);
    };

    return (
        <div className="bg-gray-900/50 rounded-2xl border border-white/10 p-6 flex flex-col items-center">
            <h3 className="text-xl font-bold text-white mb-4">Smart Allocation</h3>
            <p className="text-gray-400 text-center text-sm mb-6 max-w-xs">
                Hover over sections to see details. Visualize your portfolio diversification instantly.
            </p>

            <div className="w-full h-[300px]">
                <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                        <Pie
                            // @ts-ignore
                            activeIndex={activeIndex}
                            activeShape={renderActiveShape}
                            data={data}
                            cx="50%"
                            cy="50%"
                            innerRadius={60}
                            outerRadius={80}
                            dataKey="value"
                            onMouseEnter={onPieEnter}
                            paddingAngle={5}
                        >
                            {data.map((entry, index) => (
                                <Cell key={`cell-${index}`} fill={entry.color} stroke="none" />
                            ))}
                        </Pie>
                    </PieChart>
                </ResponsiveContainer>
            </div>

            <div className="flex gap-4 mt-4 flex-wrap justify-center">
                {data.map((item, idx) => (
                    <div
                        key={item.name}
                        className={`flex items-center gap-2 text-xs transition-opacity duration-300 ${activeIndex === idx ? 'opacity-100 font-bold' : 'opacity-50'}`}
                        onMouseEnter={() => setActiveIndex(idx)}
                    >
                        <div className="w-3 h-3 rounded-full" style={{ backgroundColor: item.color }} />
                        <span className="text-gray-300">{item.name}</span>
                    </div>
                ))}
            </div>
        </div>
    );
};
